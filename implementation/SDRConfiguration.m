classdef SDRConfiguration
    properties
        sdrDeviceName
        sdrIpAddress
        MCS
        msduLength
        channelBandwidth
        oversamplingFactor
        centerFrequency
        txGain
        idleTimeAfterEachPacket
        maxLengthOfWaveform
        lengthOfWaveformPerByte
        GUI
        displayFlag
    end
    methods (Static)
        function config = readConfigValues(configPath)
            config = SDRConfiguration;
            config.sdrDeviceName = CloudRANUtils.getConfigValue(configPath, "sdrDeviceName");
            config.sdrIpAddress = CloudRANUtils.getConfigValue(configPath, "sdrIpAddress");
            config.MCS = str2double(CloudRANUtils.getConfigValue(configPath, "MCS"));
            config.msduLength = str2double(CloudRANUtils.getConfigValue(configPath, "msduLength"));
            config.channelBandwidth = CloudRANUtils.getConfigValue(configPath, "channelBandwidth");
            config.oversamplingFactor = 1.5;
            config.centerFrequency = 2.432e9;
            config.txGain = -20;
            config.idleTimeAfterEachPacket = 20e-6;
            config.maxLengthOfWaveform = str2double(CloudRANUtils.getConfigValue(configPath, "maxLengthOfWaveform"));
            config.lengthOfWaveformPerByte = 0.000000167;
            config.GUI = strcmp(CloudRANUtils.getConfigValue(configPath, "GUI"), "true");
            config.displayFlag = strcmp(CloudRANUtils.getConfigValue(configPath, "displayFlag"), "true");
        end
    end
end