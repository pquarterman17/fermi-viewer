function result = resolveParser(filepath)
%RESOLVEPARSER  Centralized dispatcher: extension -> EM parser name.
%
%   result = parser.resolveParser('scan.dm3')
%   result = parser.resolveParser('image.tif')
%
%   Inspects file extension to determine which EM parser should handle
%   the file. Returns a struct with:
%
%       .name        - Parser function name (e.g. 'importDM3', 'importTIFF')
%       .fallback    - Fallback parser name ('' if none)
%       .isBrukerRaw - Always false here (kept for API parity with qm)
%
%   This is the EM-only subset of the original quantized_matlab
%   resolveParser. Non-EM formats (XRD, magnetometry, neutron, AFM, etc.)
%   live in the parent quantized_matlab repo.
%
%   See also IMPORTAUTO, IMPORTDM3, IMPORTTIFF

    arguments
        filepath (1,1) string {mustBeFile}
    end

    [~, ~, ext] = fileparts(filepath);
    ext = lower(ext);

    result.name        = '';
    result.fallback    = '';
    result.isBrukerRaw = false;

    switch ext
        case {'.tif', '.tiff'}
            result.name = 'importTIFF';

        case {'.jpg', '.jpeg', '.png', '.bmp', '.gif'}
            result.name = 'importImage';

        case '.bcf'
            result.name = 'importBCF';

        case '.dm3'
            result.name = 'importDM3';

        case '.dm4'
            result.name = 'importDM4';

        case '.ser'
            result.name = 'importSER';

        case {'.mrc', '.mrcs'}
            result.name = 'importMRC';

        otherwise
            error('parser:resolveParser:unknownExtension', ...
                ['No EM parser registered for extension "%s".\n' ...
                 'Supported: .tif/.tiff, .jpg/.jpeg/.png/.bmp/.gif, ' ...
                 '.bcf, .dm3/.dm4, .ser, .mrc/.mrcs\n' ...
                 'For headerless binary images use parser.importRawImage directly.\n' ...
                 'Non-EM formats (XRD, magnetometry, neutron, etc.) live in ' ...
                 'quantized_matlab: https://github.com/pquarterman17/quantized_matlab'], ext);
    end
end
