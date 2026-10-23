/**
 * Industrial HMI palette.
 *
 * The semantic names are the contract: components ask for `state-run` or
 * `state-fault`, never for a raw hex value. That keeps the colour meaning
 * consistent across every screen, and means the whole scheme can be retuned
 * for a different control-room monitor in one place.
 *
 * Colour is never the only channel. Every state also carries a text label and
 * an icon, so the interface still reads correctly for a colour-blind operator
 * and on a washed-out projector.
 */
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        // Surfaces, darkest to lightest.
        panel: {
          950: '#070a0f',
          900: '#0b0f16',
          850: '#10151f',
          800: '#151b27',
          700: '#1d2534',
          600: '#283348',
          500: '#3a4761',
        },
        ink: {
          100: '#f2f6fb',
          200: '#d5dde9',
          300: '#a9b6c9',
          400: '#8a98ae',
          500: '#7887a0',   // >= 4.7:1 on panel-800/850/900
          600: '#73829a',   // tertiary: timestamps, icons, placeholders
          700: '#4a566a',   // separators only, never text
        },
        // Machine state semantics.
        state: {
          run: '#22c55e',       // healthy / running / confirmed ON
          runDim: '#116c34',
          idle: '#64748b',      // inactive / unknown
          warn: '#f59e0b',      // warning / pending / awaiting confirmation
          warnDim: '#7c4a06',
          fault: '#ef4444',     // fault / danger
          faultDim: '#7f1d1d',
          info: '#38bdf8',      // informational / manual command / selected
          infoDim: '#0c4a6e',
          twin: '#a78bfa',      // digital-twin prediction (never live data)
          twinDim: '#4c1d95',
        },
      },
      fontFamily: {
        sans: ['Inter', 'Segoe UI', 'system-ui', 'sans-serif'],
        mono: ['JetBrains Mono', 'Cascadia Mono', 'Consolas', 'monospace'],
      },
      // Off-scale steps the state tints use (bg-state-run/12 and so on).
      // Tailwind 3 only generates the default 5-step scale without these.
      opacity: {
        6: '0.06',
        8: '0.08',
        12: '0.12',
        14: '0.14',
        18: '0.18',
      },
      boxShadow: {
        panel: '0 1px 0 0 rgba(255,255,255,0.04) inset, 0 8px 24px -12px rgba(0,0,0,0.9)',
      },
      keyframes: {
        pulseRing: {
          '0%,100%': { opacity: '0.35', transform: 'scale(1)' },
          '50%': { opacity: '0.9', transform: 'scale(1.18)' },
        },
        beltFlow: {
          from: { strokeDashoffset: '0' },
          to: { strokeDashoffset: '-24' },
        },
        sweep: {
          '0%': { transform: 'translateX(-100%)' },
          '100%': { transform: 'translateX(220%)' },
        },
      },
      animation: {
        pulseRing: 'pulseRing 1.4s ease-in-out infinite',
        beltFlow: 'beltFlow 0.7s linear infinite',
        sweep: 'sweep 1.6s ease-in-out infinite',
      },
    },
  },
  plugins: [],
}
