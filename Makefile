COFFEE=node_modules/.bin/coffee
MOCHA=node_modules/.bin/mocha
MOCHA_REPORTER?=spec
MOCHA_OPTS=--compilers coffee:coffee-script/register --globals document,window,Bling,$$,_ -R ${MOCHA_REPORTER} --bail

COFFEE_FILES=dokyu.coffee db.coffee
TEST_FILES=test/dokyu.coffee

all:

test: ${COFFEE_FILES} ${TEST_FILES}
	@$(MOCHA) $(MOCHA_OPTS)

$(MOCHA):
	npm install mocha

$(COFFEE):
	npm install coffee-script

.PHONY: test
