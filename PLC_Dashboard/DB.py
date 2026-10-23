import mysql.connector

# 1. Connect to MySQL
connection = mysql.connector.connect(
    host="localhost",
    user="root",
    password="1234",
    database="TestDB"
)

cursor = connection.cursor()

# 2. Data you want to send
a1_value = 12.5
a2_value = 100

# 3. Insert data into Sheet1
insert_query = """
INSERT INTO Sheet1 (a1, a2)
VALUES (%s, %s)
"""

cursor.execute(insert_query, (a1_value, a2_value))

# Save the data permanently
connection.commit()

print("Data inserted successfully!")

# 4. Read all data from the table
read_query = "SELECT * FROM Sheet1"

cursor.execute(read_query)

data = cursor.fetchall()

print("\nData received from MySQL:")

for row in data:
    print("a1 =", row[0], "| a2 =", row[1])

# 5. Close connection
cursor.close()
connection.close()