classdef CloudRANConfiguration
    properties
        parallelGeneration
        parallelDecoding
        parallelDecodingMode
        pregenerateWaveform
        dutyCycle
        selectiveAck
    end
    methods (Static)
        function config = readConfigValues(configPath)
            config = CloudRANConfiguration;
            config.parallelThreads = str2double(CloudRANUtils.getConfigValue(configPath, "parallelThreads"));
            config.parallelGeneration = strcmp(CloudRANUtils.getConfigValue(configPath, "parallelGeneration"), "true");
            config.parallelDecoding = strcmp(CloudRANUtils.getConfigValue(configPath, "parallelDecoding"), "true");
            config.parallelDecodingMode = CloudRANUtils.getConfigValue(configPath, "parallelDecodingMode");
            config.pregenerateWaveform = strcmp(CloudRANUtils.getConfigValue(configPath, "pregenerateWaveform"), "true");
            config.dutyCycle = str2double(CloudRANUtils.getConfigValue(configPath, "dutyCycle"));
            config.selectiveAck = strcmp(CloudRANUtils.getConfigValue(configPath, "selectiveAck"), "true");
        end
    end
end