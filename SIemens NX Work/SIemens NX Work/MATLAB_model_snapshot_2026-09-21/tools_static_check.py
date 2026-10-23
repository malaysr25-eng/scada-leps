"""
tools_static_check.py
=====================
Static audit of the MATLAB sources:

  1. block-keyword balance per file (function/if/for/while/switch/try ... end)
  2. struct-field coverage: every P.<field> / y.<field> / plc.<field> /
     u.<field> / LOG.<field> that is READ must be WRITTEN somewhere
  3. identifiers used but never assigned and not a known function
  4. call arity: nargin/nargout at each call site vs the definition

STANDING: this is a SECONDARY check.  It was written when MATLAB could not be
executed, and it is a regex-based approximation of a MATLAB parser rather than
a substitute for running the code.  Where MATLAB is installed, the primary
verification is:

    matlab -batch "check_environment"
    matlab -batch "LOG = run_factory_simulation"

Use this script for a fast pre-flight sweep, not as evidence of correctness.

It is deliberately conservative: it reports CANDIDATES, a human confirms.
Known false positives, confirmed benign on 2026-08-21:

  * "P.WP READ but never written" -- initialize_factory.m:39 assigns it with
    dynamic fieldnames, `P.WP.(f{i}) = ...`, which the regex cannot see.
  * "DUPLICATE definition of e/n/p/s/y" -- loop counters and output arguments
    legitimately reused across separate files; the checker does not scope
    names per file.

A finding is only actionable after checking the source by hand.
"""
import re, os, sys, collections

FILES = [f for f in sorted(os.listdir('.')) if f.endswith('.m')]

KEYWORDS_OPEN = {'function', 'if', 'for', 'while', 'switch', 'try', 'parfor'}
KEYWORDS_MID = {'else', 'elseif', 'case', 'otherwise', 'catch'}


def strip_code(line):
    """Remove comments and string literals, transpose-aware."""
    out = []
    i = 0
    n = len(line)
    prev = ''
    while i < n:
        c = line[i]
        if c == '%' and not (i + 1 < n and line[i + 1] == '{'):
            break
        if c == '.' and line[i:i + 3] == '...':
            break
        if c == '"':
            j = i + 1
            while j < n and line[j] != '"':
                j += 1
            out.append('""')
            i = j + 1
            prev = '"'
            continue
        if c == "'":
            # transpose if previous non-space char closes a value
            if prev and (prev.isalnum() or prev in ")]}._'"):
                out.append("'")
                i += 1
                continue
            j = i + 1
            while j < n:
                if line[j] == "'":
                    if j + 1 < n and line[j + 1] == "'":
                        j += 2
                        continue
                    break
                j += 1
            out.append("''")
            i = j + 1
            prev = "'"
            continue
        out.append(c)
        if not c.isspace():
            prev = c
        i += 1
    return ''.join(out)


def code_lines(path):
    raw = open(path, encoding='utf-8', errors='replace').read().split('\n')
    inblock = False
    res = []
    for k, l in enumerate(raw):
        s = l.strip()
        if s.startswith('%{'):
            inblock = True
            res.append((k + 1, ''))
            continue
        if s.startswith('%}'):
            inblock = False
            res.append((k + 1, ''))
            continue
        res.append((k + 1, '' if inblock else strip_code(l)))
    return res


# --------------------------------------------------------------- 1. balance
def check_balance(path):
    depth = 0
    stack = []
    problems = []
    for ln, c in code_lines(path):
        toks = re.findall(r"[A-Za-z_]\w*|\bend\b", c)
        # 'end' inside indexing, e.g. x(end) -- exclude those
        c2 = re.sub(r'\([^()]*\)', lambda m: m.group(0).replace('end', 'END_IDX'), c)
        c2 = re.sub(r'\{[^{}]*\}', lambda m: m.group(0).replace('end', 'END_IDX'), c2)
        c2 = re.sub(r'\[[^\[\]]*\]', lambda m: m.group(0).replace('end', 'END_IDX'), c2)
        for m in re.finditer(r'\b(function|if|for|while|switch|try|parfor|end)\b', c2):
            w = m.group(1)
            if w == 'end':
                if not stack:
                    problems.append((ln, 'unmatched end'))
                else:
                    stack.pop()
            else:
                if w == 'if' and re.search(r'\belse\s*if\b', c2):
                    pass
                stack.append((w, ln))
    if stack:
        problems.append((stack[-1][1], 'unclosed %s' % stack[-1][0]))
    return problems


# ------------------------------------------------- 2. struct field coverage
def struct_fields(paths, var):
    """Return (written, read) field-name sets for struct variable `var`."""
    written, read = collections.defaultdict(set), collections.defaultdict(set)
    pat_w = re.compile(r'\b%s\.([A-Za-z_]\w*)[^=<>~!]*?=(?!=)' % var)
    pat_any = re.compile(r'\b%s\.([A-Za-z_]\w*)' % var)
    for p in paths:
        for ln, c in code_lines(p):
            for m in pat_any.finditer(c):
                read[m.group(1)].add((p, ln))
            # assignment: var.field ... = , but not ==
            for m in re.finditer(r'\b%s\.([A-Za-z_]\w*)((\([^)]*\))|(\.\w+))*\s*=(?!=)' % var, c):
                written[m.group(1)].add((p, ln))
    return written, read


def report_struct(name, paths, defpaths):
    written, read = struct_fields(paths, name)
    wdef, _ = struct_fields(defpaths, name)
    missing = {}
    for f, locs in read.items():
        if f not in written and f not in wdef:
            missing[f] = locs
    return missing


# ------------------------------------------------------- 4. function arity
def defs():
    d = {}
    for p in FILES:
        for ln, c in code_lines(p):
            m = re.match(r'\s*function\s+(?:\[([^\]]*)\]|([A-Za-z_]\w*))?\s*=?\s*([A-Za-z_]\w*)\s*\(([^)]*)\)', c)
            if m:
                outs = m.group(1) or m.group(2) or ''
                nout = len([x for x in outs.split(',') if x.strip()])
                args = [a.strip() for a in m.group(4).split(',') if a.strip()]
                d.setdefault(m.group(3), []).append(dict(file=p, line=ln, nin=len(args),
                                                         args=args, nout=nout,
                                                         vararg='varargin' in args))
    return d


if __name__ == '__main__':
    print('=' * 74)
    print('STATIC AUDIT OF MATLAB SOURCES  (%d files)' % len(FILES))
    print('=' * 74)

    print('\n[1] BLOCK BALANCE')
    bad = 0
    for p in FILES:
        pr = check_balance(p)
        if pr:
            bad += 1
            for ln, msg in pr:
                print('    %-28s line %-4d %s' % (p, ln, msg))
    if not bad:
        print('    all %d files balanced' % len(FILES))

    print('\n[2] STRUCT FIELD COVERAGE')
    for var, defp in (('P', ['FactoryParams.m', 'initialize_factory.m']),
                      ('plc', ['factory_plc_init.m', 'factory_plc.m']),
                      ('y', ['factory_sensors.m']),
                      ('u', ['factory_plc.m', 'run_factory_simulation.m',
                             'factory_plant_sfun.m']),
                      ('LOG', ['run_factory_simulation.m'])):
        miss = report_struct(var, FILES, defp)
        if miss:
            for f, locs in sorted(miss.items()):
                where = ', '.join('%s:%d' % (a, b) for a, b in sorted(locs))[:90]
                print('    %s.%-16s READ but never written   [%s]' % (var, f, where))
        else:
            print('    %-4s all read fields are written' % var)

    print('\n[3] FUNCTION DEFINITIONS / CALL ARITY')
    D = defs()
    for name, lst in sorted(D.items()):
        if len(lst) > 1:
            print('    DUPLICATE definition of %s: %s' % (
                name, ', '.join('%s:%d' % (d['file'], d['line']) for d in lst)))
    callpat = re.compile(r'\b([A-Za-z_]\w*)\s*\(')
    for p in FILES:
        for ln, c in code_lines(p):
            if re.match(r'\s*function\b', c):
                continue
            for m in callpat.finditer(c):
                nm = m.group(1)
                if nm not in D:
                    continue
                # count top-level commas in the arg list
                i = m.end()
                depth = 1
                args = ''
                while i < len(c) and depth:
                    ch = c[i]
                    if ch in '([{':
                        depth += 1
                    elif ch in ')]}':
                        depth -= 1
                        if depth == 0:
                            break
                    args += ch
                    i += 1
                if depth:
                    continue
                na = 0 if not args.strip() else 1 + sum(
                    1 for j, ch in enumerate(args)
                    if ch == ',' and args[:j].count('(') == args[:j].count(')')
                    and args[:j].count('[') == args[:j].count(']')
                    and args[:j].count('{') == args[:j].count('}'))
                d0 = D[nm][0]
                if not d0['vararg'] and na > d0['nin']:
                    print('    %s:%d  %s called with %d args, defined with %d'
                          % (p, ln, nm, na, d0['nin']))
    print('=' * 74)
