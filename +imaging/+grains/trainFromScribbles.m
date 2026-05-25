function model = trainFromScribbles(img, labelMask, options)
%TRAINFROMSCRIBBLES  Train a grain pixel-classifier from sparse labels.
%
%   Syntax:
%       model = imaging.grains.trainFromScribbles(img, labelMask)
%       model = imaging.grains.trainFromScribbles(img, labelMask, Scales=[2 4 8])
%
%   The interactive ("ilastik/Weka-style") training step: the user paints a
%   few strokes labelling pixels by class (e.g. grain-type-A, grain-type-B,
%   boundary), and this fits a softmax classifier on the feature stack at
%   only the labelled pixels. The returned model is then applied to the
%   whole image (or a different image) with imaging.grains.segmentTrained.
%
%   The model carries its own feature configuration (Scales, GradientSigma)
%   so segmentTrained reproduces the IDENTICAL feature space the classifier
%   was trained on — this is what makes "train on image A, apply to image B"
%   correct rather than silently mismatched.
%
%   No external toolboxes (features via imaging.grains.extractGrainFeatures,
%   classifier via imaging.ml.softmaxTrain).
%
%   Inputs:
%       img           — [H x W] numeric grayscale image.
%       labelMask     — [H x W] integer label image: 0 = unlabelled, positive
%                       integers = class id. Only nonzero pixels are training
%                       samples. Must match size(img).
%
%   Optional Name-Value:
%       Scales        — feature scales in pixels (default [2 4]).
%       GradientSigma — feature pre-smoothing (default 0).
%       Classifier    — "softmax" (default) or "forest". Softmax is fast and
%                       linear; forest captures nonlinear feature interactions
%                       (try it if softmax underfits the orientation features).
%       LearnRate     — softmax step size (default 0.5).
%       MaxIter       — softmax iterations (default 800).
%       Lambda        — softmax L2 regularization (default 1e-3).
%       NumTrees      — forest size (default 40, Classifier="forest" only).
%       Seed          — forest RNG seed (default 0, Classifier="forest" only).
%
%   Output: model — classifier struct (imaging.ml.softmaxTrain or
%       randomForestTrain output), PLUS:
%       .scales         — feature scales used (for segmentTrained).
%       .gradientSigma  — feature pre-smoothing used.
%       .classifierType — "softmax" or "forest" (segmentTrained dispatches on it).
%       .featureNames   — {1 x F} feature names (provenance / debugging).
%
%   See also imaging.grains.segmentTrained, imaging.ml.softmaxTrain,
%            imaging.grains.extractGrainFeatures

arguments
    img                   (:,:) {mustBeNumeric}
    labelMask             (:,:) {mustBeNumeric}
    options.Scales        (1,:) double {mustBePositive} = [2 4]
    options.GradientSigma (1,1) double {mustBeNonnegative} = 0
    options.Classifier    (1,1) string {mustBeMember(options.Classifier, ["softmax","forest"])} = "softmax"
    options.LearnRate     (1,1) double {mustBePositive} = 0.5
    options.MaxIter       (1,1) double {mustBePositive, mustBeInteger} = 800
    options.Lambda        (1,1) double {mustBeNonnegative} = 1e-3
    options.NumTrees      (1,1) double {mustBePositive, mustBeInteger} = 40
    options.Seed          (1,1) double {mustBeInteger} = 0
end

if ~isequal(size(img), size(labelMask))
    error('trainFromScribbles:sizeMismatch', ...
        'img is %s but labelMask is %s.', mat2str(size(img)), mat2str(size(labelMask)));
end

labeled = labelMask > 0;
if ~any(labeled(:))
    error('trainFromScribbles:noLabels', 'labelMask has no labelled (nonzero) pixels.');
end
if numel(unique(labelMask(labeled))) < 2
    error('trainFromScribbles:oneClass', ...
        'Need at least 2 distinct classes in labelMask; found 1.');
end

% ── Features at labelled pixels ─────────────────────────────────────────
[feats, names] = imaging.grains.extractGrainFeatures(img, ...
    Scales=options.Scales, GradientSigma=options.GradientSigma);
[H, W, F] = size(feats);
X = reshape(feats, H * W, F);

idx = find(labeled);
Xlab = X(idx, :);
ylab = labelMask(idx);

% ── Train classifier ────────────────────────────────────────────────────
if options.Classifier == "forest"
    model = imaging.ml.randomForestTrain(Xlab, ylab, ...
        NumTrees=options.NumTrees, Seed=options.Seed);
else
    model = imaging.ml.softmaxTrain(Xlab, ylab, ...
        LearnRate=options.LearnRate, MaxIter=options.MaxIter, Lambda=options.Lambda);
end

% ── Bake in the feature configuration for segmentTrained ────────────────
model.scales         = options.Scales;
model.gradientSigma  = options.GradientSigma;
model.classifierType = options.Classifier;
model.featureNames   = names;
end
