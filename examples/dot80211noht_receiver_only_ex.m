%
% Example receiving 802.11 nonHT frames from E310 device using RX2-A.
%
clear;
close all;

fprintf('SDR Receiver ... \n');

%%
% Params
deviceNameSDR = 'E3xx'; % Set SDR Device
sdr_ip_addr = '192.168.4.2'; % IP address of SDR
MCS = 6;            % Modulation: 64QAM Rate: 2/3
CenterFrequency = 2.432e9;  % Channel 5
% Configure receive samples equivalent to twice the length of the
% transmitted signal, this is to ensure that PSDUs are received in order.
% On reception the duplicate MAC fragments are removed.
samplesPerFrame = 2 * 3317760; %length(txWaveform);
numMSDUs = 256; % no. of packets to receive

GUI = 1;            % debug gui stuff
displayFlag = 1; % Flag to display the decoded information

%%
if (GUI)
    % Setup handle for image plot
    if ~exist('imFig', 'var') || ~ishandle(imFig)
        imFig = figure;
        imFig.NumberTitle = 'off';
        imFig.Name = 'Image Plot';
        imFig.Visible = 'off';
    else
        clf(imFig); % Clear figure
        imFig.Visible = 'off';
    end

    % Setup Spectrum viewer
    spectrumScope = dsp.SpectrumAnalyzer( ...
        'SpectrumType',    'Power density', ...
        'SpectralAverages', 10, ...
        'YLimits',         [-130 -40], ...
        'Title',           'Received Baseband WLAN Signal Spectrum', ...
        'YLabel',          'Power spectral density');

    % Setup the constellation diagram viewer for equalized WLAN symbols
    constellation = comm.ConstellationDiagram('Title','Equalized WLAN Symbols',...
                                    'ShowReferenceConstellation',false);
end

nonHTcfg = wlanNonHTConfig;         % Create packet configuration
nonHTcfg.MCS = MCS;                  % Modulation: e.g. 6 for 64QAM Rate: 2/3
chanBW = nonHTcfg.ChannelBandwidth;

% Resample the transmit waveform at 30MHz
fs = wlanSampleRate(nonHTcfg); % Transmit sample rate in MHz
osf = 1.5;                     % OverSampling factor

                            
%%
sdrReceiver = sdrrx(deviceNameSDR, 'IPAddress', sdr_ip_addr);
sdrReceiver.BasebandSampleRate = fs*osf;
sdrReceiver.CenterFrequency = CenterFrequency;
sdrReceiver.OutputDataType = 'double';
sdrReceiver.ChannelMapping = 2; % Configure Rx channel map

requiredCaptureLength = samplesPerFrame*2;
spectrumScope.SampleRate = sdrReceiver.BasebandSampleRate;

% Get the required field indices within a PSDU
indLSTF = wlanFieldIndices(nonHTcfg,'L-STF');
indLLTF = wlanFieldIndices(nonHTcfg,'L-LTF');
indLSIG = wlanFieldIndices(nonHTcfg,'L-SIG');
Ns = indLSIG(2)-indLSIG(1)+1; % Number of samples in an OFDM symbol

% SDR Capture
fprintf('\nStarting a new RF capture.\n')

% Store twice the length of WLAN transmitted packet worth of
% samples, capturedData holds requiredCaptureLength number of baseband
% WLAN samples
capturedData = capture(sdrReceiver, requiredCaptureLength, 'Samples');

% Show power spectral density of the received waveform
if (GUI)
    spectrumScope(capturedData);
end

% Downsample the received signal
rxWaveform = resample(capturedData,fs,fs*osf);
rxWaveformLen = size(rxWaveform,1);
searchOffset = 0; % Offset from start of the waveform in samples

% Minimum packet length is 10 OFDM symbols
lstfLen = double(indLSTF(2)); % Number of samples in L-STF
minPktLen = lstfLen*5;
pktInd = 1;
sr = wlanSampleRate(nonHTcfg); % Sampling rate
fineTimingOffset = [];
packetSeq = [];
evm_rms = [];
evm_peak = [];
snr_vals = [];

% Perform EVM calculation
evmCalculator = comm.EVM('AveragingDimensions',[1 2 3]);
evmCalculator.MaximumEVMOutputPort = true;

bitsPerOctet = 8;

% Receiver processing
while (searchOffset + minPktLen) <= rxWaveformLen
    % Packet detect
    pktOffset = wlanPacketDetect(rxWaveform, chanBW, searchOffset, 0.8);

    % Adjust packet offset
    pktOffset = searchOffset+pktOffset;
    if isempty(pktOffset) || (pktOffset+double(indLSIG(2))>rxWaveformLen)
        if pktInd==1
            disp('** No packet detected **');
        end
        break;
    end

    % Extract non-HT fields and perform coarse frequency offset correction
    % to allow for reliable symbol timing
    nonHT = rxWaveform(pktOffset+(indLSTF(1):indLSIG(2)),:);
    coarseFreqOffset = wlanCoarseCFOEstimate(nonHT,chanBW);
    nonHT = helperFrequencyOffset(nonHT,fs,-coarseFreqOffset);

    % Symbol timing synchronization
    fineTimingOffset = wlanSymbolTimingEstimate(nonHT,chanBW);

    % Adjust packet offset
    pktOffset = pktOffset+fineTimingOffset;

    % Timing synchronization complete: Packet detected and synchronized
    % Extract the non-HT preamble field after synchronization and
    % perform frequency correction
    if (pktOffset<0) || ((pktOffset+minPktLen)>rxWaveformLen)
        searchOffset = pktOffset+1.5*lstfLen;
        continue;
    end
    fprintf('\nPacket-%d detected at index %d\n',pktInd,pktOffset+1);

    % Extract first 7 OFDM symbols worth of data for format detection and
    % L-SIG decoding
    nonHT = rxWaveform(pktOffset+(1:7*Ns),:);
    nonHT = helperFrequencyOffset(nonHT,fs,-coarseFreqOffset);

    % Perform fine frequency offset correction on the synchronized and
    % coarse corrected preamble fields
    lltf = nonHT(indLLTF(1):indLLTF(2),:);           % Extract L-LTF
    fineFreqOffset = wlanFineCFOEstimate(lltf,chanBW);
    nonHT = helperFrequencyOffset(nonHT,fs,-fineFreqOffset);
    cfoCorrection = coarseFreqOffset+fineFreqOffset; % Total CFO
    %cfoCorrection = 1e4;

    % Channel estimation using L-LTF
    lltf = nonHT(indLLTF(1):indLLTF(2),:);
    demodLLTF = wlanLLTFDemodulate(lltf,chanBW);
    chanEstLLTF = wlanLLTFChannelEstimate(demodLLTF,chanBW);

    % Noise estimation
    noiseVarNonHT = helperNoiseEstimate(demodLLTF);

    % SNR estimation per receive antenna
    powVHTLTF = mean(lltf.*conj(lltf));
    estimatedSNR = 10*log10(mean(powVHTLTF./noiseVarNonHT));    
    snr_vals(pktInd) = estimatedSNR;
    
    % Packet format detection using the 3 OFDM symbols immediately
    % following the L-LTF
    format = wlanFormatDetect(nonHT(indLLTF(2)+(1:3*Ns),:), ...
        chanEstLLTF,noiseVarNonHT,chanBW);
    disp(['  ' format ' format detected']);
    if ~strcmp(format,'Non-HT')
        fprintf('  A format other than Non-HT has been detected\n');
        searchOffset = pktOffset+1.5*lstfLen;
        continue;
    end

    % Recover L-SIG field bits
    [recLSIGBits,failCheck] = wlanLSIGRecover( ...
           nonHT(indLSIG(1):indLSIG(2),:), ...
           chanEstLLTF,noiseVarNonHT,chanBW);

    if failCheck
        fprintf('  L-SIG check fail \n');
        searchOffset = pktOffset+1.5*lstfLen;
        continue;
    else
        fprintf('  L-SIG check pass \n');
    end

    % Retrieve packet parameters based on decoded L-SIG
    [lsigMCS,lsigLen,rxSamples] = helperInterpretLSIG(recLSIGBits,sr);

    if (rxSamples+pktOffset)>length(rxWaveform)
        disp('** Not enough samples to decode packet **');
        break;
    end

    % Apply CFO correction to the entire packet
    rxWaveform(pktOffset+(1:rxSamples),:) = helperFrequencyOffset(...
        rxWaveform(pktOffset+(1:rxSamples),:),fs,-cfoCorrection);

    % Create a receive Non-HT config object
    rxNonHTcfg = wlanNonHTConfig;
    rxNonHTcfg.MCS = lsigMCS;
    rxNonHTcfg.PSDULength = lsigLen;

    % Get the data field indices within a PPDU
    indNonHTData = wlanFieldIndices(rxNonHTcfg,'NonHT-Data');

    % Recover PSDU bits using transmitted packet parameters and channel
    % estimates from L-LTF
    [rxPSDU,eqSym] = wlanNonHTDataRecover(rxWaveform(pktOffset+...
           (indNonHTData(1):indNonHTData(2)),:), ...
           chanEstLLTF,noiseVarNonHT,rxNonHTcfg);

    if (GUI)
        constellation(reshape(eqSym,[],1)); % Current constellation
        pause(0); % Allow constellation to repaint
        release(constellation); % Release previous constellation plot
    end

    refSym = wlanClosestReferenceSymbol(eqSym,rxNonHTcfg);
    [evm.RMS,evm.Peak] = evmCalculator(refSym,eqSym);

    evm_rms(pktInd) = evm.RMS;
    evm_peak(pktInd) = evm.Peak;
    
    % Decode the MPDU and extract MSDU
    [cfgMACRx, msduList{pktInd}, status] = wlanMPDUDecode(rxPSDU, rxNonHTcfg); %#ok<*SAGROW>

    if strcmp(status, 'Success')
        disp('  MAC FCS check pass');

        % Store sequencing information
        packetSeq(pktInd) = cfgMACRx.SequenceNumber;

        % Convert MSDU to a binary data stream
        rxBit{pktInd} = reshape(de2bi(hex2dec(cell2mat(msduList{pktInd})), 8)', [], 1);

    else % Decoding failed
        if strcmp(status, 'FCSFailed')
            % FCS failed
            disp('  MAC FCS check fail');
        else
            % FCS passed but encountered other decoding failures
            disp('  MAC FCS check pass');
        end

        % Since there are no retransmissions modeled in this example, we'll
        % extract the image data (MSDU) and sequence number from the MPDU,
        % even though FCS check fails.

        % Remove header and FCS. Extract the MSDU.
        macHeaderBitsLength = 24*bitsPerOctet;
        fcsBitsLength = 4*bitsPerOctet;
        msduList{pktInd} = rxPSDU(macHeaderBitsLength+1 : end-fcsBitsLength);

        % Extract and store sequence number
        sequenceNumStartIndex = 23*bitsPerOctet+1;
        sequenceNumEndIndex = 25*bitsPerOctet - 4;
        
        if size(rxPSDU,1) >= sequenceNumEndIndex
            packetSeq(pktInd) = bi2de(rxPSDU(sequenceNumStartIndex:sequenceNumEndIndex)');
        else
            packetSeq(pktInd) = NaN;
        end
            
        % MSDU binary data stream
        rxBit{pktInd} = double(msduList{pktInd});
    end

    % Display decoded information
    if displayFlag
        fprintf('  Estimated CFO: %5.1f Hz\n\n',cfoCorrection); %#ok<UNRCH>

        disp('  Decoded L-SIG contents: ');
        fprintf('                            MCS: %d\n',lsigMCS);
        fprintf('                         Length: %d\n',lsigLen);
        fprintf('    Number of samples in packet: %d\n\n',rxSamples);

        fprintf('  EVM:\n');
        fprintf('    EVM peak: %0.3f%%  EVM RMS: %0.3f%%\n\n', ...
        evm.Peak,evm.RMS);

        fprintf('  Decoded MAC Sequence Control field contents:\n');
        fprintf('    Sequence number:%d\n',packetSeq(pktInd));
    end

    % Update search index
    searchOffset = pktOffset+double(indNonHTData(2));

    pktInd = pktInd+1;
    % Finish processing when a duplicate packet is detected. The
    % recovered data includes bits from duplicate frame
    if length(unique(packetSeq))<length(packetSeq)
        break
    end
end

% Release the state of sdrreceiver object
release(sdrReceiver);

