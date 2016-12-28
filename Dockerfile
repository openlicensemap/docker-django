# From https://github.com/docker-library/python/blob/694a75332e8ae5ad3bfae6e8399c4d7cc3cb6181/2.7/wheezy/Dockerfile

FROM buildpack-deps:xenial

# ensure local python is preferred over distribution python
ENV PATH /usr/local/bin:$PATH

# http://bugs.python.org/issue19846
# > At the moment, setting "LANG=C" on a Linux system *fundamentally breaks Python 3*, and that's not OK.
ENV LANG C.UTF-8

# runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
		tcl \
		tk \
                wget \
                gcc \
                vim \
                ca-certificates \
                apt-utils \
	&& rm -rf /var/lib/apt/lists/*

ENV GPG_KEY C01E1CAD5EA2C4F0B8E3571504C367C218ADD4FF
ENV PYTHON_VERSION 2.7.12

# if this is called "PIP_VERSION", pip explodes with "ValueError: invalid truth value '<VERSION>'"
ENV PYTHON_PIP_VERSION 9.0.1

RUN set -ex \
	&& buildDeps=' \
		tcl-dev \
		tk-dev \
	' \
	&& apt-get update && apt-get install -y $buildDeps --no-install-recommends && rm -rf /var/lib/apt/lists/*

RUN 	wget -O python.tar.xz "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz" \
	&& wget -O python.tar.xz.asc "https://www.python.org/ftp/python/${PYTHON_VERSION%%[a-z]*}/Python-$PYTHON_VERSION.tar.xz.asc" \
        && wget -O pubkeys.txt "https://www.python.org/static/files/pubkeys.txt" \
	&& export GNUPGHOME="$(mktemp -d)" \
        && gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$GPG_KEY" \
        && gpg --batch --verify python.tar.xz.asc python.tar.xz \
	&& rm -r "$GNUPGHOME" python.tar.xz.asc

RUN 	mkdir -p /usr/src/python \
	&& tar -xJC /usr/src/python --strip-components=1 -f python.tar.xz \
	&& rm python.tar.xz \
	\
	&& cd /usr/src/python \
	&& ./configure \
		--enable-shared \
		--enable-unicode=ucs4 \
	&& make -j$(nproc) \
	&& make install \
	&& ldconfig
RUN     wget -O /tmp/get-pip.py 'https://bootstrap.pypa.io/get-pip.py' \
	&& python2 /tmp/get-pip.py "pip==$PYTHON_PIP_VERSION" \
	&& rm /tmp/get-pip.py
# we use "--force-reinstall" for the case where the version of pip we're trying to install is the same as the version bundled with Python
# ("Requirement already up-to-date: pip==8.1.2 in /usr/local/lib/python3.6/site-packages")
# https://github.com/docker-library/python/pull/143#issuecomment-241032683
RUN	pip install --no-cache-dir --upgrade --force-reinstall "pip==$PYTHON_PIP_VERSION" \
# then we use "pip list" to ensure we don't have more than one pip version installed
# https://github.com/docker-library/python/pull/100
	&& [ "$(pip list |tac|tac| awk -F '[ ()]+' '$1 == "pip" { print $2; exit }')" = "$PYTHON_PIP_VERSION" ] \
	\
	&& find /usr/local -depth \
		\( \
			\( -type d -a -name test -o -name tests \) \
			-o \
			\( -type f -a -name '*.pyc' -o -name '*.pyo' \) \
		\) -exec rm -rf '{}' + \
	&& apt-get purge -y --auto-remove $buildDeps \
	&& rm -rf /usr/src/python ~/.cache

# install "virtualenv", since the vast majority of users of this image will want it
RUN pip install --no-cache-dir virtualenv

# install django from git
# https://docs.djangoproject.com/en/1.10/topics/install/#installing-development-version
RUN apt-get install -y --no-install-recommends git
RUN mkdir -p /root/git_code/django
RUN git clone git://github.com/django/django.git /root/git_code/django

# mod_wsgi - https://www.sitepoint.com/deploying-a-django-app-with-mod_wsgi-on-ubuntu-14-04/
RUN apt-get update && apt-get install -y --no-install-recommends \
    apache2 \
    apache2-dev \
    libapache2-mod-wsgi \
    && pip install mod_wsgi \
    && rm -rf /var/lib/apt/lists/*

# PostgreSQL
RUN pip install psycopg2

# SQLite and Spatialite from source
# https://gist.github.com/tdgunes/04b9962956dd043859f5
# https://docs.djangoproject.com/en/1.10/ref/contrib/gis/install/spatialite/
RUN  apt-get update && apt-get install -y --no-install-recommends \
     build-essential \
     binutils \
     gdal-bin \
     libfreexl-dev \
     libproj-dev \
     libgeos-dev \
     libexpat1 \
     libexpat1-dev \
     pkg-config \
     python2.7-dev \
     && rm -rf /var/lib/apt/lists/*

ENV CFLAGS -I/usr/local/include
ENV LDFLAGS -L/usr/local/lib
ENV SQLITE_VERSION 3150200
ENV SPATIALITE_VERSION 4.3.0a
ENV SQLITE_YEAR 2016

# Build SQLite
RUN wget -O sqlite-autoconf.tar.gz http://sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz \
    && tar -xzvf sqlite-autoconf.tar.gz \
    && cd sqlite-autoconf-${SQLITE_VERSION} \
    && CFLAGS="-DSQLITE_ENABLE_RTREE=1" ./configure \
    && make \
    && make install \
    && cd ..

# Build SpatialLite
RUN wget -O libspatialite.tar.gz http://www.gaia-gis.it/gaia-sins/libspatialite-sources/libspatialite-${SPATIALITE_VERSION}.tar.gz \
    && tar -xzvf libspatialite.tar.gz \
    && cd libspatialite-${SPATIALITE_VERSION} \
    && ./configure \
    && make \
    && make install \
    && cd ..

# Install Django
RUN pip install -e /root/git_code/django

# Remove old versions of django
RUN python -c "import django; print(django.__path__)"

# Print the current version of django
RUN echo "-------------------------------------------------------" \
    && echo " Django installed, version: " \
    && python -c "import django;print(django.get_version())" \
    && echo "-------------------------------------------------------"

# CMD ["/bin/bash"]
# CMD  /bin/bash /root/src/start.sh
