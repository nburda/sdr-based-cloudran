# SDR-based CloudRAN

This is a Cloud Radio Access Network (CloudRAN) implementation written in MATLAB, which utilizes Software Defined Radios (SDRs) as the remote radio heads.

## Usage

First start a TCP/IP Client to receive the Data from the CloudRAN and save it in a .txt file:
```bash
nc -l 127.0.0.1 1235 > output.txt
```
Afterwards start both the CloudRAN Sender and the CloudRAN Receiver in separate MATLAB processes.
CloudRAN Sender:
```MATLAB
CloudRAN.startSender()
```
CloudRAN Receiver:
```MATLAB
CloudRAN.startReceiver()
```
To begin the actual transmission start a TCP/IP Server, which sends the data given in a .txt file to the CloudRAN:
```bash
nc 127.0.0.1 1234 < input.txt
```

## Configuration

The following tables show all configuration values, which can be adjusted in the corresponding config files, which are located inside the config folder.

### CloudRAN Sender Configuration

| Parameter | Description | Expected Format |
| :--: | :--: | :--: |
| parallelThreads | The number of parallel threads, the CloudRAN Sender should use. | Integer Value greater than 0 |
| parallelGeneration | Whether the CloudRAN Sender should use parallel generation. | Boolean |
| pipelineProtocol | Whether the CloudRAN Sender should use the pipelining protocol. | Boolean |
| dutyCycle | The procentual amount of the waveform, which should be used to transmit data. | Float between 0 and 1 |
| tcpIpIP | The IP, used to receive the data from the server. | for example 127.0.0.1 |
| tcpIpPort | The Port, used to receive the data from the server. | Integer between 1 and 65535 |
| sdrDeviceName | The device name of the SDR. | String |
| sdrIpAddress | The IP used by the SDR Sender. | for example 127.0.0.1 |
| MCS | The modulation used when generating the waveform. | Integer according to MATLABs WLAN Configuration (https://www.mathworks.com/help/wlan/ref/wlanvhtconfig.html) |
| msduLength | The length of an msdu. | Integer between 1 and 2304 |
| channelBandwidth | The bandwidth that should be used for the transmission. | String, either CBW20, CBW40, CBW80 or CBW160 |
| maxLengthOfWaveform | The maximum length of a single waveform. | Float |

### CloudRAN Receiver Configuration

| Parameter | Description | Expected Format |
| :--: | :--: | :--: |
| parallelThreads | The number of parallel threads, the CloudRAN Sender should use. | Integer Value greater than 0 |
| parallelDecoding | Whether the CloudRAN Sender should use parallel decodation. | Boolean |
| parallelDecodingMode | Which parallel decoding mode should be used when parallely decoding a waveform. | String, either Waveform or Frame |
| selectiveAck | Whether selective Acknowledgements or Go-Back-N should be used as the Acknowledgement protocol. | Boolean |
| tcpIpIP | The IP, used to send the data to the client. | for example 127.0.0.1 |
| tcpIpPort | The Port, used to send the data to the client. | Integer between 1 and 65535 |
| sdrDeviceName | The device name of the SDR. | String |
| sdrIpAddress | The IP used by the SDR Receiver. | for example 127.0.0.1 |
| MCS | The modulation used when generating the waveform. | Integer according to MATLABs WLAN Configuration (https://www.mathworks.com/help/wlan/ref/wlanvhtconfig.html) |
| msduLength | The length of an msdu. | Integer between 1 and 2304 |
| channelBandwidth | The bandwidth that should be used for the transmission. | String, either CBW20, CBW40, CBW80 or CBW160 |
| maxLengthOfWaveform | The maximum length of a single waveform. | Float |
