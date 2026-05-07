function result = executeKramersKronig(E, I)
%EXECUTEKRAMERSKRONIG  Compute dielectric function from low-loss EELS via KK analysis.
    arguments
        E   double
        I   double
    end

    res = imaging.eelsKramersKronig(E, I);

    kkFig = figure('Name', 'Kramers-Kronig Analysis');
    subplot(2,1,1);
    plot(res.energy, res.eps1, 'b-', res.energy, res.eps2, 'r-', 'LineWidth', 1.2);
    xlabel('Energy (eV)'); ylabel('\epsilon');
    legend('\epsilon_1 (real)', '\epsilon_2 (imag)'); grid on;
    title('Dielectric function');
    subplot(2,1,2);
    plot(res.energy, res.opticalConductivity, 'k-', 'LineWidth', 1.2);
    xlabel('Energy (eV)'); ylabel('\sigma_1 (S/m)');
    title('Optical conductivity'); grid on;

    result.kkResult = res;
    result.kkFig = kkFig;
    result.statusMsg = 'Kramers-Kronig analysis complete';
end
