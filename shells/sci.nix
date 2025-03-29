{pkgs, ...}:
pkgs.mkShell {
  packages = with pkgs.python3Packages; [
    pkgs.python3
    scikit-learn
    statsmodels
    matplotlib
    pandas
    polars
    pydot
    keras
    numpy
    scipy
  ];
}
