function [crcBits, apepLen, mcs] = helperInterpretSIGB(sigBBits, chanBW, isSUTx)
% helperInterpretSIGB Interpret recovered VHT-SIG-B bits
%
%   [CRCBITS, APEPLEN, MCS] = helperInterpretSIGB(SIGBBITS, CHANBW, ISSU)
%   interprets the specified VHT-SIG-B bits for the VHT format transmission
%   for a single user.
%
%   SIGBBITS is a column vector containing SIG-B bits.
%
%   CHANBW is the specified channel bandwidth. It is a character vector or
%   string and must be one of 'CBW20', 'CBW40', 'CBW80' or 'CBW160'.
%
%   ISSU is true for a single-user transmission.
%
%   CRCBITS is the checksum based on the specified bits.
%
%   APEPLEN is the APEPLength in bytes for the user of interest. This is
%   rounded to a 4-byte multiple.
%
%   MCS is the modulation coding scheme for the user of interest. This is
%   valid only for a multi-user transmission.
% 
%   See also helperVHTConfigRecover, wlanVHTConfig.

%   Copyright 2016-2017 The MathWorks, Inc.

%#codegen 

if (isSUTx)
    switch chanBW
        case 'CBW20' % 26
            apepLen = double(bi2de(sigBBits(1:17).'))*4;
            checkBits = sigBBits(1:20);   % VHT-SIG-B excluding tail
        case 'CBW40' % 27
            apepLen = double(bi2de(sigBBits(1:19).'))*4;
            checkBits = sigBBits(1:21);   % VHT-SIG-B excluding tail
        otherwise    % 29 for {'CBW80', 'CBW80+80', 'CBW160'}
            apepLen = double(bi2de(sigBBits(1:21).'))*4;
            checkBits = sigBBits(1:23);   % VHT-SIG-B excluding tail
    end
    mcs = 0; % Default, dont have this information for SU tx
else  % Multi-user
    switch chanBW
        case 'CBW20' % 26
            apepLen = double(bi2de(sigBBits(1:16).'))*4;
            mcs = double(bi2de(sigBBits(17:20).')); 
            checkBits = sigBBits(1:20);   % VHT-SIG-B excluding tail
        case 'CBW40' % 27
            apepLen = double(bi2de(sigBBits(1:17).'))*4;
            mcs = double(bi2de(sigBBits(18:21).')); 
            checkBits = sigBBits(1:21);   % VHT-SIG-B excluding tail
        otherwise    % 29 for {'CBW80', 'CBW80+80', 'CBW160'}
            apepLen = double(bi2de(sigBBits(1:19).'))*4;
            mcs = double(bi2de(sigBBits(20:23).')); 
            checkBits = sigBBits(1:23);   % VHT-SIG-B excluding tail
    end    
end

crcBits = wlan.internal.wlanCRCGenerate(checkBits);

end