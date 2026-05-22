function result = executeELNES(E, I, onset, fitWindow)
%EXECUTEELNES  Extract near-edge fine structure (ELNES) from EELS spectrum.
    arguments
        E         double
        I         double
        onset     double
        fitWindow (1,2) double
    end

    res = imaging.eelsELNES(E, I, 'EdgeOnset', onset, 'FitWindow', fitWindow);

    elnesFig = figure('Name', 'ELNES');
    plot(res.relativeEnergy, res.intensity, 'b-', 'LineWidth', 1.5);
    xlabel('Energy relative to onset (eV)'); ylabel('Normalized intensity');
    title(sprintf('ELNES at %.0f eV (jump=%.1f)', onset, res.edgeJump));
    grid on;

    result.elnesResult = res;
    result.elnesFig = elnesFig;
    result.statusMsg = sprintf('ELNES extracted: onset=%.0f eV', onset);
end
