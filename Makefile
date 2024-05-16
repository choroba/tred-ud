SHELL := /bin/bash
EXTENSION_DIR := $(HOME)/SVN/tred/extensions
VALIDATE := $(HOME)/SVN/pml/bin/pml_validate

documentation: ud/documentation/index.html

ud/documentation/index.html: README.pod ud/package.xml
	update-copyright.pl $<
	-mkdir ud/documentation
	pod2html $< > $@
	rm pod2htmd.tmp

release: ud
	$(EXTENSION_DIR)/release_extension \
	-u http://ufal.mff.cuni.cz/tred/extensions/external \
	-r ufal:/usr/share/drupal7/legacy/tred/extensions/external \
	-d $< \
	-m r \
	-p $(VALIDATE)

.PHONY: documentation release
