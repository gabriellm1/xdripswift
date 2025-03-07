import Foundation
import CoreBluetooth
import os

class CGMG5Transmitter:BluetoothTransmitter, BluetoothTransmitterDelegate, CGMTransmitter {
    
    // MARK: - properties
    
    /// G5 or G6 transmitter firmware version - only used internally, if nil then it was  never received
    ///
    /// created public because inheriting classes need it
    var firmwareVersion:String?
    
    // MARK: UUID's
    
    // advertisement
    let CBUUID_Advertisement_G5 = "0000FEBC-0000-1000-8000-00805F9B34FB"
    
    // service
    let CBUUID_Service_G5 = "F8083532-849E-531C-C594-30F1F86A4EA5"
    
    // characteristic uuids (created them in an enum as there's a lot of them, it's easy to switch through the list)
    private enum CBUUID_Characteristic_UUID:String, CustomStringConvertible  {
        
        // Read/Notify characteristic
        case CBUUID_Communication = "F8083533-849E-531C-C594-30F1F86A4EA5"
        
        // Write/Indicate - write characteristic
        case CBUUID_Write_Control = "F8083534-849E-531C-C594-30F1F86A4EA5"
        
        // Read/Write/Indicate - Read Characteristic
        case CBUUID_Receive_Authentication = "F8083535-849E-531C-C594-30F1F86A4EA5"
        
        // Read/Write/Notify
        case CBUUID_Backfill = "F8083536-849E-531C-C594-30F1F86A4EA5"

        /// for logging, returns a readable name for the characteristic
        var description: String {
            switch self {
                
            case .CBUUID_Communication:
                return "Communication"
            case .CBUUID_Write_Control:
                return "Write_Control"
            case .CBUUID_Receive_Authentication:
                return "Receive_Authentication"
            case .CBUUID_Backfill:
                return "Backfill"
            }
        }
    }

    // MARK: other
    
    /// the write and control Characteristic
    private var writeControlCharacteristic:CBCharacteristic?
    
    /// the receive and authentication Characteristic
    private var receiveAuthenticationCharacteristic:CBCharacteristic?
    
    /// the communication Characteristic
    private var communicationCharacteristic:CBCharacteristic?
    
    /// the backfill Characteristic
    private var backfillCharacteristic:CBCharacteristic?

    //timestamp of last reading
    private var timeStampOfLastG5Reading:Date
    
    //timestamp of last battery read
    private var timeStampOfLastBatteryReading:Date
    
    //timestamp of transmitterReset
    private var timeStampTransmitterReset:Date
    
    /// transmitterId
    private let transmitterId:String

    /// will be used to pass back bluetooth and cgm related events
    private(set) weak var cgmTransmitterDelegate:CGMTransmitterDelegate?
    
    /// for trace
    private let log = OSLog(subsystem: ConstantsLog.subSystem, category: ConstantsLog.categoryCGMG5)
    
    /// is G5 reset necessary or not
    private var G5ResetRequested:Bool
    
    /// used as parameter in call to cgmTransmitterDelegate.cgmTransmitterInfoReceived, when there's no glucosedata to send
    var emptyArray: [GlucoseData] = []
    
    // for creating testreadings
    private var testAmount:Double = 150000.0
    
    /// true if pairing request was done, and waiting to see if pairing was done
    private var waitingPairingConfirmation = false
    
    // MARK: - functions
    
    /// - parameters:
    ///     - address: if already connected before, then give here the address that was received during previous connect, if not give nil
    ///     - name : if already connected before, then give here the name that was received during previous connect, if not give nil
    ///     - transmitterID: expected transmitterID, 6 characters
    init?(address:String?, name: String?, transmitterID:String, delegate:CGMTransmitterDelegate) {
        //verify if transmitterid is 6 chars and allowed chars
        guard transmitterID.count == 6 else {
            trace("transmitterID length not 6, init CGMG5Transmitter fails", log: log, type: .error)
            return nil
        }

        //verify allowed chars
        let regex = try! NSRegularExpression(pattern: "[a-zA-Z0-9]", options: .caseInsensitive)
        guard transmitterID.validate(withRegex: regex) else {
            trace("transmitterID has non-allowed characters a-zA-Z0-9", log: log, type: .error)
            return nil
        }

        // assign addressname and name or expected devicename
        var newAddressAndName:BluetoothTransmitter.DeviceAddressAndName = BluetoothTransmitter.DeviceAddressAndName.notYetConnected(expectedName: "DEXCOM" + transmitterID[transmitterID.index(transmitterID.startIndex, offsetBy: 4)..<transmitterID.endIndex])
        if let address = address {
            newAddressAndName = BluetoothTransmitter.DeviceAddressAndName.alreadyConnectedBefore(address: address, name: name)
        }
        
        // set timestampoflastg5reading to 0
        self.timeStampOfLastG5Reading = Date(timeIntervalSince1970: 0)
        
        //set timeStampOfLastBatteryReading to 0
        self.timeStampOfLastBatteryReading = Date(timeIntervalSince1970: 0)
        
        //set timeStampTransmitterReset to 0
        self.timeStampTransmitterReset = Date(timeIntervalSince1970: 0)

        //assign transmitterId
        self.transmitterId = transmitterID
        
        // initialize G5ResetRequested
        self.G5ResetRequested = false

        // initialize - CBUUID_Receive_Authentication.rawValue and CBUUID_Write_Control.rawValue will probably not be used in the superclass
        super.init(addressAndName: newAddressAndName, CBUUID_Advertisement: CBUUID_Advertisement_G5, servicesCBUUIDs: [CBUUID(string: CBUUID_Service_G5)], CBUUID_ReceiveCharacteristic: CBUUID_Characteristic_UUID.CBUUID_Receive_Authentication.rawValue, CBUUID_WriteCharacteristic: CBUUID_Characteristic_UUID.CBUUID_Write_Control.rawValue, startScanningAfterInit: CGMTransmitterType.dexcomG5.startScanningAfterInit())

        //assign CGMTransmitterDelegate
        cgmTransmitterDelegate = delegate
        
        // set self as delegate for BluetoothTransmitterDelegate - this parameter is defined in the parent class BluetoothTransmitter
        bluetoothTransmitterDelegate = self
        
        // start scanning
        _ = startScanning()
    }
    
    /// for testing , make the function public and call it after having activate a sensor in rootviewcontroller
    ///
    /// amount is rawvalue for testreading, should be number like 150000
    private func temptesting(amount:Double) {
        testAmount = amount
        Timer.scheduledTimer(timeInterval: 60 * 5, target: self, selector: #selector(self.createTestReading), userInfo: nil, repeats: true)
    }
    
    /// for testing, used by temptesting
    @objc private func createTestReading() {
        let testdata = GlucoseData(timeStamp: Date(), glucoseLevelRaw: testAmount, glucoseLevelFiltered: testAmount)
        debuglogging("timestamp testdata = " + testdata.timeStamp.description + ", with amount = " + testAmount.description)
        var testdataasarray = [testdata]
        cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &testdataasarray, transmitterBatteryInfo: nil, sensorState: nil, sensorTimeInMinutes: nil, firmware: nil, hardware: nil, hardwareSerialNumber: nil, bootloader: nil, sensorSerialNumber: nil)
        testAmount = testAmount + 1
    }
    
    // MARK: public functions
    
    /// scale the rawValue, dependent on transmitter version G5 , G6 --
    /// for G6, there's two possible scaling factors, depending on the firmware version. For G5 there's only one, firmware version independent
    /// - parameters:
    ///     - firmwareVersion : for G6, the scaling factor is firmware dependent. Parameter created optional although it is known at the moment the function is used
    ///     - the value to be scaled
    /// this function can be override in CGMG6Transmitter, which can then return the scalingFactor , firmware dependent
    func scaleRawValue(firmwareVersion: String?, rawValue: Double) -> Double {
        
        // for G5, the scaling is independent of the firmwareVersion
        // and there's no scaling to do
        return rawValue
        
    }
    
    // MARK: CBCentralManager overriden functions
    
    override func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
            // will probably never come here because reconnect doesn't happen with scanning, hence diddiscover will never be called excep the very first time that an app tries to connect to a G5
            trace("diddiscover peripheral, but last reading was less than 1 minute ago, will ignore", log: log, type: .info)
        } else {
            super.centralManager(central, didDiscover: peripheral, advertisementData: advertisementData, rssi: RSSI)
        }
    }

    override func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        
        // if last reading was less than a minute ago, then no need to continue, otherwise continue with process by calling super.centralManager(central, didConnect: peripheral)
        if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
            trace("connected, but last reading was less than 1 minute ago", log: log, type: .info)
            // don't disconnect here, keep the connection open, the transmitter will disconnect in a few seconds, assumption is that this will increase battery life
        } else {
            super.centralManager(central, didConnect: peripheral)
        }
        
        // to be sure waitingPairingConfirmation is reset to false
        waitingPairingConfirmation = false
    }
    
    override func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        trace("didDiscoverCharacteristicsFor", log: log, type: .info)
        
        // log error if any
        if let error = error {
            trace("    error: %{public}@", log: log, type: .error , error.localizedDescription)
        }
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                
                if let characteristicValue = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) {

                    trace("    characteristic : %{public}@", log: log, type: .info, characteristicValue.description)
                    
                    switch characteristicValue {
                    case .CBUUID_Backfill:
                        backfillCharacteristic = characteristic
                        
                    case .CBUUID_Write_Control:
                        writeControlCharacteristic = characteristic
                        
                    case .CBUUID_Communication:
                        communicationCharacteristic = characteristic
                        
                    case .CBUUID_Receive_Authentication:
                        receiveAuthenticationCharacteristic = characteristic
                        trace("    calling setNotifyValue true", log: log, type: .info)
                        peripheral.setNotifyValue(true, for: characteristic)
                        
                    }
                } else {
                    trace("    characteristic UUID unknown : %{public}@", log: log, type: .error, characteristic.uuid.uuidString)
                }
            }
        } else {
            trace("characteristics is nil. There must be some error.", log: log, type: .error)
        }
    }
    
    // MARK: CGMTransmitter protocol functions
    
    /// to ask pairing
    func initiatePairing() {
        // assuming that the transmitter is effectively awaiting the pairing, otherwise this obviously won't work
        sendPairingRequest()
    }
    
    /// to ask transmitter reset
    func reset(requested:Bool) {
        G5ResetRequested = requested
    }
    
    /// this transmitter does not support oopWeb
    func setWebOOPEnabled(enabled: Bool) {
    }
    
    /// this transmitter does not support oop web
    func setWebOOPSiteAndToken(oopWebSite: String, oopWebToken: String) {}
    
    // MARK: BluetoothTransmitterDelegate functions
    
    func centralManagerDidConnect(address:String?, name:String?) {
        cgmTransmitterDelegate?.cgmTransmitterDidConnect(address: address, name: name)
    }
    
    func centralManagerDidFailToConnect(error: Error?) {
    }
    
    func centralManagerDidUpdateState(state: CBManagerState) {
        // if status changed to poweredon, and if address = nil then superclass will not start the scanning
        // but for DexcomG5 we can start scanning
        if state == .poweredOn {
            if (address() == nil) {
                    _ = startScanning()
            }
        }

        cgmTransmitterDelegate?.deviceDidUpdateBluetoothState(state: state)
    }
    
    func centralManagerDidDisconnectPeripheral(error: Error?) {
        
        if waitingPairingConfirmation {
            // device has requested a pairing request and is now in a status of verifying if pairing was successfull or not, this by doing setNotify to writeCharacteristic. If a disconnect occurs now, it means pairing has failed (probably because user didn't approve it
            waitingPairingConfirmation = false
            
            // inform delegate
            cgmTransmitterDelegate?.pairingFailed()
        }
        
        // inform delegate
        cgmTransmitterDelegate?.cgmTransmitterDidDisconnect()
    }
    
    func peripheralDidUpdateNotificationStateFor(characteristic: CBCharacteristic, error: Error?) {
        trace("in peripheralDidUpdateNotificationStateFor", log: log, type: .info)
        
        if let error = error {
            trace("    error: %{public}@", log: log, type: .error , error.localizedDescription)
        }
        
        if let characteristicValue = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) {
            
            trace("    characteristic : %{public}@", log: log, type: .info, characteristicValue.description)
            
            switch characteristicValue {
                
            case .CBUUID_Write_Control:
                if (G5ResetRequested) {
                    // send ResetTxMessage
                    sendG5Reset()
                    
                    //reset G5ResetRequested to false
                    G5ResetRequested = false
                    
                } else {
                    // send SensorTxMessage to transmitter
                    getSensorData()
                }
                
            case .CBUUID_Receive_Authentication:
                //send AuthRequestTxMessage
                sendAuthRequestTxMessage()
                
            default:
                break
            }
        } else {
            trace("    characteristicValue is nil", log: log, type: .error)
        }
    }
    
    func peripheralDidUpdateValueFor(characteristic: CBCharacteristic, error: Error?) {
        
        guard let characteristic_UUID = CBUUID_Characteristic_UUID(rawValue: characteristic.uuid.uuidString) else {
           trace("in peripheralDidUpdateValueFor, unknown characteristic received with uuid = %{public}@", log: log, type: .error, characteristic.uuid.uuidString)
            return
        }
        
        trace("in peripheralDidUpdateValueFor, characteristic uuid = %{public}@", log: log, type: .info, characteristic_UUID.description)
        
        if let error = error {
            trace("error: %{public}@", log: log, type: .error , error.localizedDescription)
        }
        
        if let value = characteristic.value {
            
            //only for logging
            let data = value.hexEncodedString()
            trace("    data = %{public}@", log: log, type: .debug, data)
            
            //check type of message and process according to type
            if let firstByte = value.first {
                if let opCode = DexcomTransmitterOpCode(rawValue: firstByte) {
                    trace("    opcode = %{public}@", log: log, type: .info, opCode.description)
                    switch opCode {
                        
                    case .authChallengeRx:
                        if let authChallengeRxMessage = AuthChallengeRxMessage(data: value) {
                            
                            // if not paired, then send message to delegate
                            if !authChallengeRxMessage.paired {
                                
                                trace("    transmitter needs pairing, calling sendKeepAliveMessage", log: log, type: .info)
                                
                                // will send keep alive message
                                sendKeepAliveMessage()
                                
                                // delegate needs to be informed that pairing is needed
                                cgmTransmitterDelegate?.cgmTransmitterNeedsPairing()
                                
                            } else {

                                // subscribe to writeControlCharacteristic
                                if let writeControlCharacteristic = writeControlCharacteristic {
                                    setNotifyValue(true, for: writeControlCharacteristic)
                                } else {
                                    trace("    writeControlCharacteristic is nil, can not set notifyValue", log: log, type: .error)
                                }

                            }
                            
                        } else {
                            trace("    failed to create authChallengeRxMessage", log: log, type: .info)
                        }
                        
                    case .authRequestRx:
                        if let authRequestRxMessage = AuthRequestRxMessage(data: value), let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
                            
                            guard let challengeHash = CGMG5Transmitter.computeHash(transmitterId, of: authRequestRxMessage.challenge) else {
                                trace("    failed to calculate challengeHash, no further processing", log: log, type: .error)
                                return
                            }
                            
                            let authChallengeTxMessage = AuthChallengeTxMessage(challengeHash: challengeHash)
                            _ = writeDataToPeripheral(data: authChallengeTxMessage.data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
                            
                        } else {
                            trace("    writeControlCharacteristic is nil or authRequestRxMessage is nil", log: log, type: .error)
                        }
                        
                    case .sensorDataRx:
                        
                        // if this is the first sensorDataRx after a successful pairing, then inform delegate that pairing is finished
                        if waitingPairingConfirmation {
                            waitingPairingConfirmation = false
                            cgmTransmitterDelegate?.successfullyPaired()
                        }
                        
                        if let sensorDataRxMessage = SensorDataRxMessage(data: value) {
                            
                            if firmwareVersion != nil {
                                
                                // transmitterversion was already recceived, let's see if we need to get the batterystatus
                                if Date() > Date(timeInterval: ConstantsDexcomG5.batteryReadPeriodInHours * 60 * 60, since: timeStampOfLastBatteryReading) {
                                    trace("    last battery reading was long time ago, requesting now", log: log, type: .info)
                                    if let writeControlCharacteristic = writeControlCharacteristic {
                                        _ = writeDataToPeripheral(data: BatteryStatusTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
                                        timeStampOfLastBatteryReading = Date()
                                    } else {
                                        trace("    writeControlCharacteristic is nil, can not send BatteryStatusTxMessage", log: log, type: .error)
                                    }
                                } else {
                                    disconnect()
                                }
                            } else {
                                
                                if let writeControlCharacteristic = writeControlCharacteristic {
                                    _ = writeDataToPeripheral(data: TransmitterVersionTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
                                } else {
                                    trace("    writeControlCharacteristic is nil, can not send TransmitterVersionTxMessage", log: log, type: .error)
                                }
                            }
                            
                            //if reset was done recently, less than 5 minutes ago, then ignore the reading
                            if Date() < Date(timeInterval: 5 * 60, since: timeStampTransmitterReset) {
                                trace("    last transmitter reset was less than 5 minutes ago, ignoring this reading", log: log, type: .info)
                            //} else if sensorDataRxMessage.unfiltered == 0.0 {
                              //  trace("    sensorDataRxMessage.unfiltered = 0.0, ignoring this reading", log: log, type: .info)
                            } else {
                                if Date() < Date(timeInterval: 60, since: timeStampOfLastG5Reading) {
                                    // should probably never come here because this check is already done at connection time
                                    trace("    last reading was less than 1 minute ago, ignoring", log: log, type: .info)
                                } else {
                                    timeStampOfLastG5Reading = Date()
                                    
                                    let glucoseData = GlucoseData(timeStamp: sensorDataRxMessage.timestamp, glucoseLevelRaw: scaleRawValue(firmwareVersion: firmwareVersion, rawValue: sensorDataRxMessage.unfiltered), glucoseLevelFiltered: scaleRawValue(firmwareVersion: firmwareVersion, rawValue: sensorDataRxMessage.unfiltered))
                                    
                                    var glucoseDataArray = [glucoseData]
                                    
                                    cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &glucoseDataArray, transmitterBatteryInfo: nil, sensorState: nil, sensorTimeInMinutes: nil, firmware: nil, hardware: nil, hardwareSerialNumber: nil, bootloader: nil, sensorSerialNumber: nil)
                                }
                            }
                            
                        } else {
                            trace("    sensorDataRxMessagee is nil", log: log, type: .error)
                        }
                        
                    case .resetRx:
                        
                        processResetRxMessage(value: value)
                        
                    case .batteryStatusRx:
                        
                        processBatteryStatusRxMessage(value: value)
                        
                    case .transmitterVersionRx:
                        
                        processTransmitterVersionRxMessage(value: value)
                        
                    case .keepAliveRx:
                        
                        // seems no processing is necessary, now the user should get a pairing requeset
                        break
                        
                    case .paireRequestRx:
                        
                        // don't know if the user accepted the pairing request or not, we can only know by trying to subscribe to writeControlCharacteristic - if the device is paired, we'll receive a sensorDataRx message, if not paired, then a disconnect will happen
                        
                        // set status to waitingForPairingConfirmation
                        waitingPairingConfirmation = true
                        
                        // setNotifyValue
                        if let writeControlCharacteristic = writeControlCharacteristic {
                            setNotifyValue(true, for: writeControlCharacteristic)
                        } else {
                            trace("    writeControlCharacteristic is nil, can not set notifyValue", log: log, type: .error)
                        }
                        
                    default:
                        trace("    unknown opcode received ", log: log, type: .error)
                        break
                    }
                } else {
                    trace("    value doesn't start with a known opcode = %{public}d", log: log, type: .error, firstByte)
                }
            } else {
                trace("    characteristic.value is nil", log: log, type: .error)
            }
        }
    }

    // MARK: helper functions
    
    /// sends SensorTxMessage to transmitter
    private func getSensorData() {
        trace("sending getsensordata", log: log, type: .info)
        if let writeControlCharacteristic = writeControlCharacteristic {
            _ = writeDataToPeripheral(data: SensorDataTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
        } else {
            trace("    writeControlCharacteristic is nil, not getsensordata", log: log, type: .error)
        }
    }
    
    /// sends G5 reset to transmitter
    private func sendG5Reset() {
        trace("sending G5Reset", log: log, type: .info)
        if let writeControlCharacteristic = writeControlCharacteristic {
            _ = writeDataToPeripheral(data: ResetTxMessage().data, characteristicToWriteTo: writeControlCharacteristic, type: .withResponse)
            G5ResetRequested = false
        } else {
            trace("    writeControlCharacteristic is nil, not sending G5 reset", log: log, type: .error)
        }
    }
    
    /// sends AuthRequestTxMessage to transmitter
    private func sendAuthRequestTxMessage() {
        let authMessage = AuthRequestTxMessage()
        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
            _ = writeDataToPeripheral(data: authMessage.data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
        } else {
            trace("receiveAuthenticationCharacteristic is nil", log: log, type: .error)
        }
    }
    
    private func processResetRxMessage(value:Data) {
        if let resetRxMessage = ResetRxMessage(data: value) {
            if resetRxMessage.status == 0 {
                trace("resetRxMessage status is 0, considering reset successful", log: log, type: .info)
                cgmTransmitterDelegate?.reset(successful: true)
            } else {
                trace("resetRxMessage status is %{public}d, considering reset failed", log: log, type: .info, resetRxMessage.status)
                cgmTransmitterDelegate?.reset(successful: false)
            }
        } else {
            trace("resetRxMessage is nil", log: log, type: .error)
        }
    }
    
    private func processBatteryStatusRxMessage(value:Data) {
        if let batteryStatusRxMessage = BatteryStatusRxMessage(data: value) {
            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &emptyArray, transmitterBatteryInfo: TransmitterBatteryInfo.DexcomG5(voltageA: batteryStatusRxMessage.voltageA, voltageB: batteryStatusRxMessage.voltageB, resist: batteryStatusRxMessage.resist, runtime: batteryStatusRxMessage.runtime, temperature: batteryStatusRxMessage.temperature), sensorState: nil, sensorTimeInMinutes: nil, firmware: nil, hardware: nil, hardwareSerialNumber: nil, bootloader: nil, sensorSerialNumber: nil)
        } else {
            trace("batteryStatusRxMessage is nil", log: log, type: .error)
        }
    }
    
    private func processTransmitterVersionRxMessage(value:Data) {
        if let transmitterVersionRxMessage = TransmitterVersionRxMessage(data: value) {
            
            cgmTransmitterDelegate?.cgmTransmitterInfoReceived(glucoseData: &emptyArray, transmitterBatteryInfo: nil, sensorState: nil, sensorTimeInMinutes: nil, firmware: transmitterVersionRxMessage.firmwareVersion.hexEncodedString(), hardware: nil, hardwareSerialNumber: nil, bootloader: nil, sensorSerialNumber: nil)
            
            // assign transmitterVersion
            firmwareVersion = transmitterVersionRxMessage.firmwareVersion.hexEncodedString()
            
        } else {
            trace("transmitterVersionRxMessage is nil", log: log, type: .error)
        }
    }

    /// calculates encryptionkey
    private static func cryptKey(_ id:String) -> Data? {
        return "00\(id)00\(id)".data(using: .utf8)
    }
    
    /// compute hash
    private static func computeHash(_ id:String, of data: Data) -> Data? {
        guard data.count == 8 else {
            return nil
        }
        
        var doubleData = Data(capacity: data.count * 2)
        doubleData.append(data)
        doubleData.append(data)
        
        if let cryptKey = cryptKey(id) {
            if let outData = try? AESCrypt.encryptData(doubleData, usingKey: cryptKey) {
                return outData[0..<8]
            }
        }
        return nil
    }

    /// sends pairing request to transmitter, this will result in an iOS generated pairing request
    private func sendPairingRequest() {
        
        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
            
            _ = writeDataToPeripheral(data: PairRequestTxMessage().data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)

        } else {
            trace("    in sendBondingRequest, receiveAuthenticationCharacteristic is nil, can not send KeepAliveTxMessage", log: log, type: .error)
        }

    }

    /// sends a keepalive message, this will keep the connection with the transmitter open for 60 seconds
    private func sendKeepAliveMessage() {

        if let receiveAuthenticationCharacteristic = receiveAuthenticationCharacteristic {
            
            // to make sure the Dexcom doesn't disconnect the next 60 seconds, this gives the user sufficient time to accept the pairing request, which will come next
            _ = writeDataToPeripheral(data: KeepAliveTxMessage(time: UInt8(ConstantsDexcomG5.maxTimeToAcceptPairingInSeconds)).data, characteristicToWriteTo: receiveAuthenticationCharacteristic, type: .withResponse)
            
        } else {
            trace("    in sendKeepAliveMessage, receiveAuthenticationCharacteristic is nil, can not send KeepAliveTxMessage", log: log, type: .error)
        }

    }
}
