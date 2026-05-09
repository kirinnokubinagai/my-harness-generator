# Custom Nix derivation for `codex-app-server-sdk` (PyPI), used by the
# my-harness-generator runtime. Not yet in nixpkgs. Build backend: hatchling.
#
# License: AGPL-3.0-or-later (per upstream pyproject.toml). We use the
# package as a library — no redistribution implications for the harness.
{ lib
, buildPythonPackage
, fetchPypi
, hatchling
, pydantic
, websockets
}:

buildPythonPackage rec {
  pname = "codex-app-server-sdk";
  version = "0.3.2";
  pyproject = true;

  src = fetchPypi {
    # PyPI normalises the dist name to underscores; fetchPypi handles this.
    pname = "codex_app_server_sdk";
    inherit version;
    hash = "sha256-qyGjdJIq2NXSmQTIlFPtucC8zWlxntBsfsfGboK9u9Q=";
  };

  build-system = [ hatchling ];

  dependencies = [
    pydantic
    websockets
  ];

  # Upstream tests aren't shipped in the sdist (they live under tests/ in the
  # source tree but require a running codex daemon). Skip during build.
  doCheck = false;

  pythonImportsCheck = [ "codex_app_server_sdk" ];

  meta = with lib; {
    description = "Async Python client for codex app-server over stdio and websocket";
    homepage = "https://github.com/emsi/codex-app-server-sdk";
    license = licenses.agpl3Plus;
    maintainers = [ ];
  };
}
