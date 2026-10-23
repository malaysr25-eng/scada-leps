import snap7

# Define PLC connection parameters
# For S7-1200, the default rack is 0 and slot is 1
PLC_IP = "172.21.30.157"
RACK = 0
SLOT = 1

# Create a client instance
client = snap7.client.Client()

try:
    # Attempt to connect to the PLC
    print(f"Connecting to PLC at {PLC_IP}...")
    client.connect(PLC_IP, RACK, SLOT)
    
    # Check if the client is successfully connected
    if client.get_connected():
        print(f"connected {PLC_IP}")
        
        # Disconnect cleanly after confirmation
        client.disconnect()
    else:
        print("Failed to establish a stable connection.")

except Exception as e:
    print(f"Error connecting to PLC: {e}")
    print("\nTroubleshooting tips:")
    print("1. Ensure your PC's IP address is set to something like 172.21.30.158.")
    print("2. Ensure you can ping 172.21.30.157 from your command prompt.")
    print("3. In TIA Portal, check 'Permit access with PUT/GET communication' in the CPU Protection properties.")
