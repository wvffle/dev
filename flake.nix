{
  outputs = {self, ...}: {
    templates = rec {
      slidev = {
        path = ./templates/slidev;
        description = "A slidev presentation";
      };

      slides = slidev;
    };
  };
}
