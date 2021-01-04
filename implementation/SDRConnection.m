% This class provides all necessary functions for the SDR connection.

classdef SDRConnection
    properties
        sdrDeviceName
        sdrIpAddress
        channelBandwidth
        oversamplingFactor {mustBeNumeric, mustBePositive}
        centerFrequency {mustBeNumeric}
        waveformPlayTime {mustBeNumeric}
        txGain {mustBeNumeric}
        maxWaveformLen {mustBeNumeric, mustBePositive}
        GUI
    end
    methods (Static)
        
        % Send waveform via SDR.
        function sdrTransmitter = transmitWaveform(config, waveform)
            VHTcfg = wlanVHTConfig;
            VHTcfg.ChannelBandwidth = config.channelBandwidth;
            sampleRate = wlanSampleRate(VHTcfg);
            
            sdrTransmitter = sdrtx(config.sdrDeviceName, 'IPAddress', config.sdrIpAddress);
            
            sdrTransmitter.BasebandSampleRate = sampleRate*config.oversamplingFactor;
            sdrTransmitter.CenterFrequency = config.centerFrequency;
            sdrTransmitter.ShowAdvancedProperties = true;
            sdrTransmitter.BypassUserLogic = true;
            sdrTransmitter.Gain = config.txGain;
            sdrTransmitter.ChannelMapping = 2;
            
            CloudRANUtils.dispMessage(...
                "Uploading waveform to SDR platform for TX");
            
            sdrTransmitter.transmitRepeat(waveform);
        end
        
        % Receive waveform via SDR.
        function waveform = receiveWaveform(config)
            VHTcfg = wlanVHTConfig;    
            VHTcfg.ChannelBandwidth = config.channelBandwidth;
            sampleRate = wlanSampleRate(VHTcfg); 
            
            sdrReceiver = sdrrx(config.sdrDeviceName, 'IPAddress', config.sdrIpAddress);
            sdrReceiver.BasebandSampleRate = sampleRate*config.oversamplingFactor;
            sdrReceiver.CenterFrequency = config.centerFrequency;
            sdrReceiver.OutputDataType = 'double';
            sdrReceiver.ChannelMapping = 2;
            
            requiredCaptureLength = config.maxLengthOfWaveform * 2;
            
            CloudRANUtils.dispMessage("Starting a new RF capture for " + requiredCaptureLength + "s.");
            
            waveform = capture(sdrReceiver, requiredCaptureLength, 'Seconds');
            
            release(sdrReceiver);
            
            if (config.GUI && usejava('desktop'))
                % Setup Spectrum viewer
                spectrumScope = dsp.SpectrumAnalyzer( ...
                    'SpectrumType',    'Power density', ...
                    'SpectralAverages', 10, ...
                    'YLimits',         [-130 -40], ...
                    'Title',           'Received Baseband WLAN Signal Spectrum', ...
                    'YLabel',          'Power spectral density');
                
                spectrumScope.SampleRate = sdrReceiver.BasebandSampleRate;
                spectrumScope(waveform);
            end
        end
    end
end