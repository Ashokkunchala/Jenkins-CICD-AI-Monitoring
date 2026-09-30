.PHONY: test build package clean

test:
	python3 -m unittest discover -s tests -v

build:
	python3 -m py_compile app.py

package:
	mkdir -p dist
	tar -czf dist/jenkins-cicd-ai-lab-$${BUILD_NUMBER:-local}.tar.gz app.py tests README.md

clean:
	rm -rf dist __pycache__ tests/__pycache__
