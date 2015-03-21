COFFEE=node_modules/.bin/coffee
MOCHA=node_modules/.bin/mocha
MOCHA_REPORTER?=spec
MOCHA_OPTS=--compilers coffee:coffee-script/register --globals document,window,Bling,$$,_ -R ${MOCHA_REPORTER} --bail

COFFEE_FILES=$(shell ls src/*.coffee)
TEST_FILES=test/dokyu.coffee
JS_FILES=$(shell ls src/*.coffee | sed -e 's/src/lib/' -e 's/coffee/js/')

all: ${JS_FILES}
	@echo "Done."

lib/%.js: src/%.coffee
	@echo $< '>' $@
	@mkdir -p $(shell dirname $@) && sed -e 's/# .*$$//' $< | cpp -w | ${COFFEE} -sc > $@

test: ${JS_FILES} ${TEST_FILES}
	@${MOCHA} ${MOCHA_OPTS}

${MOCHA}:
	npm install mocha

${COFFEE}:
	npm install coffee-script

.PHONY: test
