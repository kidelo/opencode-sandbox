# ==========================================================================
# base-full.Dockerfile — precompiled "full" pseudo base (ocs-base-full).
#
# NOT a selectable profile (name does not match the Dockerfile.* glob).
# `ocs rebuild` builds it into the local image `ocs-base-full` BEFORE a
# `full` profile build, so the expensive full toolchain (the dev apt set +
# the large pip data/office/PDF/OCR/sci stack) is installed ONCE per host and
# reused by EVERY full-profile project. A `Dockerfile.full` build on top is
# then just the per-project tail (squid/firewall config, password, entrypoint)
# — seconds, not minutes.
#
# Layers on ocs-base (the common harness: apt base set, dev user + dirs,
# opencode CLI, xdg-open stub). Together ocs-base + ocs-base-full make the
# full profile a 2-level precompile:
#   python:3.13-slim-bookworm  <-  ocs-base   <-  ocs-base-full  <-  Dockerfile.full (per-project tail)
#
# Rebuilt automatically when OCS_BASE API changes (bump in bin/ocs-rebuild-container)
# or the host uid:gid changes (the dev user is baked with them).
# ==========================================================================

FROM ocs-base

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Already in ocs-base (do NOT re-declare): build-essential, curl,
# ca-certificates, git, xdg-utils, gosu, procps, squid, iptables, iproute2,
# iputils-ping, netcat-openbsd, dnsutils, whois.

# Deliberately NOT installed (see AGENTS.md):
#   sudo — privilege-escalation; the red-team suite treats "sudo: not found" as the block
#   libreoffice*, pandoc, imagemagick, exiftool, …  — heavy native document tools
#   gdal-bin, libgdal-dev, proj-bin, libproj-dev, … — geospatial + HPC stack
#   tshark, wireshark-common — clashes with the firewall
#   torch, tensorflow, jax, transformers, cuda-* — GPU / DL stack
#   opencv* — not needed for this sandbox

# ============================================================================
# OS PACKAGES — the full dev toolchain (precompiled, shared, uid-agnostic)
# ============================================================================
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        \
        # Development / shell
        pkg-config \
        wget \
        shellcheck \
        \
        # CLI / search / file management
        coreutils \
        findutils \
        file \
        tree \
        rename \
        moreutils \
        parallel \
        fd-find \
        ripgrep \
        jq \
        yq \
        xmlstarlet \
        \
        # Data-processing CLI
        csvkit \
        miller \
        \
        # Archives / compression / file detection
        tar \
        gzip \
        bzip2 \
        xz-utils \
        zstd \
        lz4 \
        zip \
        unzip \
        p7zip-full \
        unrar-free \
        libarchive-tools \
        libmagic1 \
        \
        # User / process / sandbox
        psmisc \
        \
        # Networking / sandbox
        net-tools \
        \
        # MySQL / database clients
        default-libmysqlclient-dev \
        mariadb-client \
        freetds-dev \
        \
        # PDF / document utilities
        poppler-utils \
        qpdf \
        mupdf-tools \
        ghostscript \
        \
        # OCR
        tesseract-ocr \
        tesseract-ocr-eng \
        tesseract-ocr-deu \
        tesseract-ocr-osd \
        \
        # Graphviz + fonts
        graphviz \
        fonts-dejavu \
        fonts-liberation \
        fonts-liberation2 \
        fonts-noto-core \
        fonts-noto-cjk \
        \
        # XML / HTML native dependencies
        libxml2-dev \
        libxslt1-dev \
        \
        # WeasyPrint / cairosvg / PDF rendering
        libpango-1.0-0 \
        libpangoft2-1.0-0 \
        libharfbuzz0b \
        libharfbuzz-subset0 \
        libfontconfig1 \
        libfreetype6 \
        libfreetype6-dev \
        libffi-dev \
        libcairo2 \
        \
        # Image / render native libs
        libjpeg62-turbo \
        libjpeg-dev \
        libpng16-16 \
        libpng-dev \
        libtiff-dev \
        libwebp-dev \
        libopenjp2-7-dev \
        libheif1 \
        \
    && rm -rf /var/lib/apt/lists/*

# fd-find ships as `fdfind` on Debian; symlink so `fd` works out of the box.
RUN if [ -x /usr/bin/fdfind ]; then \
        ln -sf /usr/bin/fdfind /usr/local/bin/fd; \
    fi

# ============================================================================
# PYTHON PACKAGES — data + office + PDF + HTML + OCR + ML (precompiled)
# Intentionally NO: torch/tf/jax/… GPU stack; xgboost; pyxlsb
# ============================================================================
RUN python -m pip install --no-cache-dir --upgrade pip setuptools wheel \
    && python -m pip install --no-cache-dir \
        \
        # DATABASES
        mysqlclient \
        PyMySQL \
        SQLAlchemy \
        alembic \
        psycopg[binary] \
        pymssql \
        redis \
        \
        # DATA / TABLES
        pandas \
        scipy \
        polars \
        pyarrow \
        pandera \
        openpyxl \
        xlsxwriter \
        xlrd \
        python-calamine \
        xlsx2csv \
        yearfrac==0.4.8 \
        formulas \
        xlcalculator \
        pyexcel-io \
        pyexcel-xlsx \
        python-dateutil \
        pytz \
        tzdata \
        \
        # VALIDATION / SERIALIZATION / CONFIG
        pydantic \
        pydantic-settings \
        PyYAML \
        toml \
        tomli \
        orjson \
        jsonschema \
        jsonpath-ng \
        jsonlines \
        jmespath \
        python-dotenv \
        \
        # HTTP / REST / API
        requests \
        httpx \
        urllib3 \
        aiohttp \
        websockets \
        \
        # HTML / XML / SCRAPING
        beautifulsoup4 \
        lxml \
        html5lib \
        selectolax \
        feedparser \
        \
        # PDF
        pypdf \
        pypdfium2 \
        pdf2image \
        PyMuPDF \
        pdfplumber \
        pdfminer.six \
        pikepdf \
        pdfrw \
        borb \
        reportlab \
        weasyprint \
        fpdf2 \
        camelot-py \
        \
        # OCR
        pytesseract \
        \
        # OFFICE — python only (no libreoffice/pandoc)
        odfpy \
        python-docx \
        docx2txt \
        mammoth \
        docxcompose \
        docxtpl \
        python-docx-replace \
        docx2python \
        docx-mailmerge \
        python-pptx \
        pptx-tools \
        markdown \
        \
        # IMAGES / SVG / DOCUMENT SUPPORT
        Pillow \
        qrcode \
        cairosvg \
        svglib \
        \
        # ARCHIVES / FILES
        rarfile \
        py7zr \
        filetype \
        python-magic \
        \
        # TEXT / PARSING / SEARCH
        chardet \
        charset-normalizer \
        rapidfuzz \
        python-slugify \
        \
        # CALENDAR / TIME
        icalendar \
        humanize \
        \
        # CLI / TERMINAL
        rich \
        tqdm \
        click \
        typer \
        tabulate \
        great-tables \
        \
        # RETRIES / FILE WATCHING / SYSTEM
        tenacity \
        watchdog \
        psutil \
        \
        # SECURITY / CRYPTO / OFFICE-FILE PARSERS
        cryptography \
        bcrypt \
        passlib \
        msoffcrypto-tool \
        olefile \
        mail-parser \
        extract-msg \
        \
        # MARKDOWN / HTML CONVERSIONS
        markdown-it-py \
        mistune \
        markdownify \
        html2text \
        mdformat \
        python-frontmatter \
        markitdown \
        \
        # SCIENCE — cluster A: arrays / big-data
        xarray \
        dask \
        zarr \
        sparse \
        numexpr \
        \
        # SCIENCE — cluster B: plotting
        matplotlib \
        seaborn \
        plotly \
        bokeh \
        \
        # SCIENCE — cluster C: classical ML (xgboost dropped)
        scikit-learn \
        statsmodels \
        lightgbm
