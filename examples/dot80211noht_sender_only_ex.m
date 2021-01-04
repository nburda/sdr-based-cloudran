%
% Example sending 802.11 nonHT frames from E310 device using TRX-A
%

clear;
close all;

fprintf('SDR Transmitter ... \n');

%%
% Params
sdr_ip_addr = '192.168.3.2'; % IP address of SDR
txGain = -20;       % set the tx gain: seems not to work
msduLength = 2304;  % MSDU length in bytes
MCS = 6;            % Modulation: 64QAM Rate: 2/3
CenterFrequency = 2.432e9;  % Channel 5
idleTimeAfterEachPacket = 20e-6;
wf_play_time = 20;   % play waveform for 2s
GUI = 0;            % debug gui stuff

%%                            
%  Initialize SDR device
deviceNameSDR = 'E3xx'; % Set SDR Device

%%
% Input an image file and convert to binary stream
fileTx = 'peppers.png';            % Image file name
fData = imread(fileTx);            % Read image data from file
scale = 1;                       % Image scaling factor
origSize = size(fData);            % Original input image size
scaledSize = max(floor(scale.*origSize(1:2)),1); % Calculate new image size
heightIx = min(round(((1:scaledSize(1))-0.5)./scale+0.5),origSize(1));
widthIx = min(round(((1:scaledSize(2))-0.5)./scale+0.5),origSize(2));
fData = fData(heightIx,widthIx,:); % Resize image
imsize = size(fData);              % Store new image size
txImage = fData(:);

% size on app layer
app_payload_sz = size(txImage,1);
fprintf('Size on app layer: %d Bytes\n', app_payload_sz);

numMSDUs = ceil(length(txImage)/msduLength);
padZeros = msduLength-mod(length(txImage),msduLength);
txData = [txImage; zeros(padZeros,1)];
txDataBits = double(reshape(de2bi(txData, 8)', [], 1));

%
% Divide input data stream into fragments (frames)
bitsPerOctet = 8;
data = zeros(0, 1);

% size on MAC layer
mpdu_payload_sz = 0;

for ind=0:numMSDUs-1
    % Extract image data (in octets) for each MPDU
    frameBody = txData(ind*msduLength+1:msduLength*(ind+1),:);

    % Create MAC frame configuration object and configure sequence number
    cfgMAC = wlanMACFrameConfig('FrameType', 'Data', 'SequenceNumber', ind);

    % Generate MPDU
    [mpdu, lengthMPDU] = wlanMACFrame(frameBody, cfgMAC);

    % Convert MPDU bytes to a bit stream
    psdu = reshape(de2bi(hex2dec(mpdu), 8)', [], 1);

    % Concatenate PSDUs for waveform generation
    data = [data; psdu]; %#ok<AGROW>
    
    mpdu_payload_sz = mpdu_payload_sz + lengthMPDU;
end

fprintf('Size on MAC layer: %d Bytes, %f x app\n', mpdu_payload_sz, (mpdu_payload_sz/app_payload_sz));

%%
nonHTcfg = wlanNonHTConfig;         % Create packet configuration
nonHTcfg.MCS = MCS;                  % Modulation: e.g. 6 for 64QAM Rate: 2/3
nonHTcfg.NumTransmitAntennas = 1;   % Number of transmit antenna
chanBW = nonHTcfg.ChannelBandwidth;
nonHTcfg.PSDULength = lengthMPDU;   % Set the PSDU length

%%

% Initialize the scrambler with a random integer for each packet
scramblerInitialization = randi([1 127],numMSDUs,1);

% Generate baseband NonHT packets separated by idle time
txWaveform = wlanWaveformGenerator(data,nonHTcfg, ...
    'NumPackets',numMSDUs,'IdleTime',idleTimeAfterEachPacket, ...
    'ScramblerInitialization',scramblerInitialization);

bb_waveform_sz = size(txWaveform,1) * 4;
fprintf('Size on PHY layer (BB): %d Bytes, %f x app\n', bb_waveform_sz, (bb_waveform_sz/app_payload_sz));

% Resample the transmit waveform at 30MHz
fs = wlanSampleRate(nonHTcfg); % Transmit sample rate in MHz
osf = 1.5;                     % OverSampling factor

txWaveform  = resample(txWaveform,fs*osf,fs);

bb_res_waveform_sz = size(txWaveform,1) * 4;
fprintf('Size on PHY layer (resampled BB): %d Bytes, %f x app\n', bb_res_waveform_sz, (bb_res_waveform_sz/app_payload_sz));

time = ((0:length(txWaveform)-1)/(fs*osf))*1e6;

if (GUI)
    plot(time, abs(txWaveform))
    xlabel ('Time (microseconds)');
    ylabel('Magnitude');
end

waveform_duration_sec = max(time) / 1e6;
waveform_data_rate = bb_res_waveform_sz * (1/waveform_duration_sec) * 8;

fprintf('Generating WLAN transmit waveform of %f sec, rate %f Gbps\n', waveform_duration_sec, waveform_data_rate/1e9)

% Scale the normalized signal to avoid saturation of RF stages
powerScaleFactor = 0.8;
txWaveform = txWaveform.*(1/max(abs(txWaveform))*powerScaleFactor);
% Cast the transmit signal to int16, this is the native format for the SDR
% hardware
txWaveform = int16(txWaveform*2^15);

%%
sdrTransmitter = sdrtx(deviceNameSDR, 'IPAddress', sdr_ip_addr); % Transmitter properties

sdrTransmitter.BasebandSampleRate = fs*osf;
sdrTransmitter.CenterFrequency = CenterFrequency;
sdrTransmitter.ShowAdvancedProperties = true;
sdrTransmitter.BypassUserLogic = true;
sdrTransmitter.Gain = txGain;
sdrTransmitter.ChannelMapping = 2;         % Apply TX channel mapping

fprintf('Uploading waveform to SDR platform for TX w/ play time of %f sec\n', wf_play_time);
tic
sdrTransmitter.transmitRepeat(txWaveform);

% amount of time to transmit waveform in loop
pause(wf_play_time);
fprintf('... waveform stopped\n');

% Release the state of sdrTransmitter and receiver object
release(sdrTransmitter);
