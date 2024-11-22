ACLOCAL_AMFLAGS = -I platform/vita/m4
SUBDIRS = src
EXTRA_DIST = changes.txt license.txt readme.md \
	platform/vita/love.desktop.in
dist_man1_MANS = platform/vita/love.6

applicationsdir=$(datarootdir)/applications
mimeinfodir=$(datarootdir)/mime/packages
pixmapsdir=$(datarootdir)/pixmaps
mimeiconsdir=$(datarootdir)/icons/hicolor/scalable/mimetypes

applications_DATA = platform/vita/love.desktop
dist_mimeinfo_DATA = platform/vita/love.xml
dist_pixmaps_DATA = platform/vita/love.svg
dist_mimeicons_DATA = platform/vita/application-x-love-game.svg

platform/vita/love.desktop: platform/vita/love.desktop.in
	$(MKDIR_P) platform/vita
	rm -f $@ $@.tmp
	$(SED) \
		-e "s|@bindir[@]|$(bindir)|" \
		${srcdir}/$@.in > $@.tmp
	chmod a-w $@.tmp
	mv $@.tmp $@
