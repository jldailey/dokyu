COFFEE=node_modules/.bin/coffee
MOCHA=node_modules/.bin/mocha
MOCHA_OPTS=--compilers coffee:coffee-script --globals document,window,Bling,$$,_ -R spec

COFFEE_FILES=index.coffee db.coffee
PASS_FILES=test/document.coffee.pass

all:

test: $(PASS_FILES)

test/%.pass: test/% $(COFFEE_FILES) $(MOCHA) $(COFFEE) Makefile
	$(MOCHA) $(MOCHA_OPTS) $< && touch $@

$(MOCHA):
	npm install mocha

$(COFFEE):
	npm install coffee-script

