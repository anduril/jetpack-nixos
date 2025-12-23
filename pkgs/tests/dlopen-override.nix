{ stdenv
, dlopenOverride
, writeShellScriptBin
}:
let
  normal = stdenv.mkDerivation {
    name = "test-app";

    src = ./dlopen-libs;

    buildPhase = ''
      cc -shared -o lib1.so -fPIC test-lib1.c
      cc -shared -o lib2.so -fPIC test-lib2.c
      cc -o main test-app.c -ldl
    '';

    installPhase = ''
      install -Dm755 lib1.so "$out"/lib/lib1.so
      install -Dm755 lib2.so "$out"/lib/lib2.so
      install -Dm755 main "$out"/bin/main
    '';
  };

  override = stdenv.mkDerivation {
    name = "test-app-override";

    src = ./dlopen-libs;

    buildPhase = ''
      cc -shared -o lib1.so -fPIC test-lib1.c
      cc -shared -o lib2.so -fPIC test-lib2.c
      cc -o main test-app.c -ldl
    '';

    installPhase = ''
      install -Dm755 lib1.so "$out"/lib/lib1.so
      install -Dm755 lib2.so "$out"/lib/lib2.so
      install -Dm755 main "$out"/bin/main
    '';

    preFixup = ''
      postFixupHooks+=('
        ${ dlopenOverride { "./lib1.so" = "./lib2.so"; } "$out/bin/main" }
      ')
    '';
  };
in
writeShellScriptBin "dlopen-override-test" ''
  cd ${normal}/lib
  output=$(${normal}/bin/main)
    
  if [[ $output != "Hello, I am lib1" ]]; then
    echo "expected Hello, I am lib1 got $output" 
    exit 1
  fi

  cd ${override}/lib
  output=$(${override}/bin/main)
    
  if [[ $output != "Hello, I am lib2" ]]; then
    echo "expected Hello, I am lib2 got $output" 
    exit 1
  fi

  echo "dlopen-override is working as expected!"
''
