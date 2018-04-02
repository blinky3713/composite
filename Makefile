
.PHONY: build update-build clean reallyclean sdist

build: update-build
	stack test --nix --ghc-options="-Wall -Werror"

update-build:
	nix-shell update-build-shell.nix --run ./update-build.sh

clean:
	stack clean

reallyclean:
	rm -rf .stack-work */.stack-work _sdists

sdist: reallyclean build
	stack sdist
	mkdir -p _sdists
	cp */.stack-work/dist/*/*/*.tar.gz _sdists

hlint:
	hlint composite-aeson "--ignore=Parse error" -XTypeApplications
	hlint composite-aeson-refined "--ignore=Parse error" -XTypeApplications
	hlint composite-base "--ignore=Parse error" -XTypeApplications
	hlint composite-ekg "--ignore=Parse error" -XTypeApplications
	hlint composite-opaleye "--ignore=Parse error" -XTypeApplications
	hlint composite-swagger "--ignore=Parse error" -XTypeApplications
	hlint example "--ignore=Parse error" -XTypeApplications

stylish:
	find ./composite-* -name "*.hs" | xargs stylish-haskell -c ./.stylish_haskell.yaml -i
	find ./example -name "*.hs" | xargs stylish-haskell -c ./.stylish_haskell.yaml -i
