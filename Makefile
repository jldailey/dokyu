COFFEE=node_modules/.bin/coffee
MOCHA=node_modules/.bin/mocha
MOCHA_OPTS=--compilers coffee:coffee-script --globals document,window,Bling,$$,_ -R spec

COFFEE_FILES=dokyu.coffee db.coffee
PASS_FILES=test/dokyu.coffee.pass

all:

test: $(PASS_FILES)

test/%.pass: test/% $(COFFEE_FILES) $(MOCHA) $(COFFEE) Makefile
	@echo Running $<...
	@$(MOCHA) $(MOCHA_OPTS) $< && touch $@

$(MOCHA):
	npm install mocha

$(COFFEE):
	npm install coffee-script

