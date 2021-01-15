% This class provides all necessary functions for the SDR connection.

classdef SDRConnection
    methods (Static)
        
        % This method sends a given waveform via the SDR.
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
        
        % This method receives a waveform via the SDR.
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
        end
    end
end