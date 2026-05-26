classdef AtomColumnWorkshopModel < handle
%ATOMCOLUMNWORKSHOPMODEL  State container for the atom-column workshop.
%
%   Holds the image, detection/fit/strain parameters, and results for the
%   atom-column analysis window (FermiViewer's functional-with-handle-state
%   convention — the orchestrator stays procedural; this class only owns
%   state). All heavy computation lives in +imaging/+atoms; this class never
%   calls it — the workshop does, and writes results back here.
%
%   See also fermiViewer.atomcolumns.openAtomColumnWorkshop,
%            imaging.atoms.detectColumns, imaging.atoms.fitGaussian2D,
%            imaging.atoms.peakPairStrain

    properties
        image      double = []        % grayscale image under analysis
        pixelSize  double = NaN        % calibration (units/px), NaN if uncal
        pixelUnit  string = "px"

        % ── Detection / fit parameters ──────────────────────────────────
        polarity   string = "bright"   % "bright" | "dark"
        sigma      double = 2           % pre-smooth sigma (px)
        threshold  double = 0.2         % relative intensity threshold [0,1]
        minSep     double = 8           % NMS / min column separation (px)
        winRadius  double = 6           % Gaussian-fit window half-size (px)

        % ── Sublattice / strain parameters ──────────────────────────────
        numSublattices double = 1       % k-means sublattice count
        overlay    string = "markers"   % markers|sublattice|exx|eyy|exy|rotation

        % ── Results ─────────────────────────────────────────────────────
        positions  double = zeros(0,2)  % sub-pixel (x,y)
        amplitude  double = zeros(0,1)
        sublattice double = zeros(0,1)
        lattice    struct = struct('valid', false)   % findLatticeVectors output
        strain     struct = struct('valid', false)   % peakPairStrain output
        meanRsq    double = NaN
    end

    methods
        function obj = AtomColumnWorkshopModel(image, pixelSize, pixelUnit)
            if nargin >= 1 && ~isempty(image), obj.image = double(image); end
            if nargin >= 2 && ~isempty(pixelSize), obj.pixelSize = pixelSize; end
            if nargin >= 3 && ~isempty(pixelUnit), obj.pixelUnit = string(pixelUnit); end
        end

        function tf = hasColumns(obj)
            tf = size(obj.positions, 1) > 0;
        end

        function tf = hasStrain(obj)
            tf = isfield(obj.strain, 'valid') && obj.strain.valid;
        end

        function reset(obj)
            obj.positions  = zeros(0,2);
            obj.amplitude  = zeros(0,1);
            obj.sublattice = zeros(0,1);
            obj.lattice    = struct('valid', false);
            obj.strain     = struct('valid', false);
            obj.meanRsq    = NaN;
        end
    end
end
