function buildROIManager(roiList, btnColors, hook)
%BUILDROIMANAGER  Modal ROI manager with statistics table and CSV export.
    arguments
        roiList   cell
        btnColors struct
        hook      struct
    end

    rmFig = uifigure('Name', 'ROI Manager', ...
        'Position', [280 200 500 350]);
    rmGL = uigridlayout(rmFig, [2 1], ...
        'RowHeight', {'1x', 30}, 'Padding', [6 6 6 6]);

    if isempty(roiList)
        tData = {};
    else
        tData = cell(numel(roiList), 6);
        for ri = 1:numel(roiList)
            roi = roiList{ri};
            tData{ri, 1} = roi.name;
            tData{ri, 2} = sprintf('[%d:%d, %d:%d]', roi.xMin, roi.xMax, roi.yMin, roi.yMax);
            tData{ri, 3} = sprintf('%.1f', roi.stats.mean);
            tData{ri, 4} = sprintf('%.1f', roi.stats.std);
            tData{ri, 5} = sprintf('%.1f', roi.stats.min);
            tData{ri, 6} = sprintf('%.1f', roi.stats.max);
        end
    end

    uit = uitable(rmGL, ...
        'ColumnName', {'Name', 'Region', 'Mean', 'Std', 'Min', 'Max'}, ...
        'ColumnWidth', {80, 120, 60, 60, 60, 60});
    uit.Layout.Row = 1;
    if ~isempty(tData)
        uit.Data = tData;
    end

    btnRowRM = uigridlayout(rmGL, [1 3], ...
        'ColumnWidth', {80, 80, '1x'}, 'Padding', [0 0 0 0]);
    btnRowRM.Layout.Row = 2;

    uibutton(btnRowRM, 'Text', 'Add ROI', ...
        'BackgroundColor', btnColors.primary, 'FontColor', btnColors.fg, ...
        'ButtonPushedFcn', @(~,~) addROI());
    uibutton(btnRowRM, 'Text', 'Export CSV', ...
        'BackgroundColor', btnColors.export, 'FontColor', btnColors.fg, ...
        'ButtonPushedFcn', @(~,~) exportROIs());

    function addROI()
        hook.startROICapture();
    end

    function exportROIs()
        currentROIs = hook.getROIList();
        if isempty(currentROIs), return; end
        [fn, fp] = uiputfile('*.csv', 'Export ROIs');
        if isequal(fn, 0), return; end
        fid = fopen(fullfile(fp, fn), 'w');
        fprintf(fid, 'Name,xMin,xMax,yMin,yMax,Mean,Std,Min,Max,Area\n');
        for eri = 1:numel(currentROIs)
            roi = currentROIs{eri};
            fprintf(fid, '%s,%d,%d,%d,%d,%.4f,%.4f,%.4f,%.4f,%d\n', ...
                roi.name, roi.xMin, roi.xMax, roi.yMin, roi.yMax, ...
                roi.stats.mean, roi.stats.std, roi.stats.min, roi.stats.max, roi.stats.area);
        end
        fclose(fid);
        hook.setStatus(sprintf('Exported %d ROIs to %s', numel(currentROIs), fn));
    end
end
