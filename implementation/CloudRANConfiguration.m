% This class stores the configuration values which are related to the
% general CloudRAN Execution.
classdef CloudRANConfiguration
    properties
        parallelThreads
        parallelGeneration
        parallelDecoding
        parallelDecodingMode
        pipelineProtocol
        dutyCycle
        selectiveAck
    end
    methods (Static)
        % This method reads all CloudRAN related configuration values from a given
        % config file.
        function config = readConfigValues(configPath)
            config = CloudRANConfiguration;
            config.parallelThreads = str2double(CloudRANUtils.getConfigValue(configPath, "parallelThreads"));
            config.parallelGeneration = strcmp(CloudRANUtils.getConfigValue(configPath, "parallelGeneration"), "true");
            config.parallelDecoding = strcmp(CloudRANUtils.getConfigValue(configPath, "parallelDecoding"), "true");
            config.parallelDecodingMode = CloudRANUtils.getConfigValue(configPath, "parallelDecodingMode");
            config.pipelineProtocol = strcmp(CloudRANUtils.getConfigValue(configPath, "pipelineProtocol"), "true");
            config.dutyCycle = str2double(CloudRANUtils.getConfigValue(configPath, "dutyCycle"));
            config.selectiveAck = strcmp(CloudRANUtils.getConfigValue(configPath, "selectiveAck"), "true");
        end
    end
end