# Sample Requirements — Wafer Unload Operation

Small example to verify the skill end-to-end. Generates ~4 test cases.

## Feature: Unload Wafer from Chuck

### Use Cases

**UC1 — Basic unload from chuck (happy path)**
- User selects a wafer on the chuck and clicks Unload
- System moves wafer to the assigned carrier slot
- Final state: wafer in carrier, chuck empty

**UC2 — Unload when carrier slot is occupied**
- User clicks Unload but the destination slot is already filled
- System must display error: "Carrier slot N is occupied"
- No movement of the wafer should occur

**UC3 — Unload during interlock condition**
- Safety interlock is active (door open / E-stop)
- System must block the unload and raise safety flag
- Operator notification must be visible

### Requirements

- **R1**: System shall move wafer from chuck to assigned carrier slot when Unload is initiated
- **R2**: System shall verify carrier slot is empty before initiating unload
- **R3**: System shall display clear error messages for blocked operations
- **R4**: System shall enforce safety interlocks and raise safety flags on violation
- **R5**: System shall log all unload operations with timestamp + operator ID

### Expected Coverage

- Positive flow: UC1
- Negative flow + recovery: UC2 (error → clear slot → retry → success)
- Safety: UC3 (interlock blocks operation + flag raised)
