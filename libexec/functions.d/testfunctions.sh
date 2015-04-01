#!/bin/bash
# Copyright 2014 David Spencer, Baildon, West Yorkshire, U.K.
# All rights reserved.  For licence details, see the file 'LICENCE'.
#-------------------------------------------------------------------------------
# testfunctions.sh - functions for various quality assurance tests in slackrepo
#   test_slackbuild
#   test_download
#   test_package
#-------------------------------------------------------------------------------

function test_slackbuild
# Test prgnam.SlackBuild, slack-desc, prgnam.info and README files
# $1 = itemid
# Return status:
# 0 = all good
# 1 = the test found something
# 2 = significant error
{
  local itemid="$1"
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local itemdir="${ITEMDIR[$itemid]}"
  local itemfile="${ITEMFILE[$itemid]}"
  local retstat=0

  local PRGNAM VERSION HOMEPAGE
  local DOWNLOAD DOWNLOAD_${SR_ARCH}
  local MD5SUM MD5SUM_${SR_ARCH} SHA256SUM SHA256SUM_${SR_ARCH}
  local REQUIRES MAINTAINER EMAIL

  local slackdesc hr linecount

  log_normal -a "Testing SlackBuild files ... "


  #-----------------------------#
  # (1) prgnam.SlackBuild
  #-----------------------------#

  # Not sure how this could happen, but...
  [ -f "$SR_SBREPO"/"$itemdir"/"$itemfile" ] || \
    { log_error -a "${itemid}: $itemfile not found"; return 2; }


  #-----------------------------#
  # (2) slack-desc
  #-----------------------------#

  slackdesc="$SR_SBREPO"/"$itemdir"/slack-desc
  if [ -f "$slackdesc" ]; then
    hr='|-----handy-ruler------------------------------------------------------|'
    # check <=13 line description
    linecount=$(grep -c "^${itemprgnam}:" "$slackdesc")
    [ "$linecount" -gt 13 ] && \
      { log_warning -a "${itemid}: slack-desc: $linecount lines of description"; retstat=1; }
    # check handy ruler
#   if ! grep -q "^[[:blank:]]*$hr\$" "$slackdesc" ; then
#     { log_warning -a "${itemid}: slack-desc: handy-ruler is corrupt or missing"; retstat=1; }
#   elif [ "$(grep "^[[:blank:]]*$hr\$" "$slackdesc" | sed "s/|.*|//" | wc -c)" -ne $(( ${#itemprgnam} + 1 )) ]; then
#     { log_warning -a "${itemid}: slack-desc: handy-ruler is misaligned"; retstat=1; }
#   fi
    # check line length <= 80
    [ "$(grep "^${itemprgnam}:" "$slackdesc" | sed "s/^${itemprgnam}://" | wc -L)" -gt 80 ] && \
      { log_warning -a "${itemid}: slack-desc: description lines too long"; retstat=1; }
    # check appname (i.e. $itemprgnam)
    grep -q -v -e '^#' -e "^${itemprgnam}:" -e '^[[:blank:]]*$' -e '^[[:blank:]]*|-.*-|$' -e 'THIS FILE' "$slackdesc"  && \
      { log_warning -a "${itemid}: slack-desc: unrecognised text (appname wrong?)"; retstat=1; }
  else
    { log_warning -a "${itemid}: slack-desc not found"; retstat=1; }
  fi


  #-----------------------------#
  # (3) prgnam.info
  #-----------------------------#

  if [ -f "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info ]; then
    unset PRGNAM VERSION HOMEPAGE DOWNLOAD MD5SUM SHA256SUM REQUIRES MAINTAINER EMAIL
    . "$SR_SBREPO"/"$itemdir"/"$itemprgnam".info
    [ "$PRGNAM" = "$itemprgnam" ] || \
      { log_warning -a "${itemid}: PRGNAM in $itemprgnam.info is '$PRGNAM' (expected $itemprgnam)"; retstat=1; }
    [ -n "$VERSION" ] || \
      { log_warning -a "${itemid}: VERSION not set in $itemprgnam.info"; retstat=1; }
    [ -v HOMEPAGE ] || \
      { log_warning -a "${itemid}: HOMEPAGE not set in $itemprgnam.info"; retstat=1; }
      # Don't bother testing the homepage URL - parked domains give false negatives
    [ -v DOWNLOAD ] || \
      { log_warning -a "${itemid}: DOWNLOAD not set in $itemprgnam.info"; retstat=1; }
    [ -v MD5SUM ] || \
      { log_warning -a "${itemid}: MD5SUM not set in $itemprgnam.info"; retstat=1; }
    #### check it's valid hex md5sum, same number of sums as downloads
    #### check DOWNLOAD_arch & MD5SUM_arch
    #### don't do checks on unofficial SHA256SUM at the moment
    [ -v REQUIRES ] || \
      { log_warning -a "${itemid}: REQUIRES not set in $itemprgnam.info"; retstat=1; }
    [ -v MAINTAINER ] || \
      { log_warning -a "${itemid}: MAINTAINER not set in $itemprgnam.info"; retstat=1; }
    [ -v EMAIL ] || \
      { log_warning -a "${itemid}: EMAIL not set in $itemprgnam.info"; retstat=1; }
  elif [ "$OPT_REPO" = 'SBo' ]; then
    { log_warning -a "${itemid}: $itemprgnam.info not found"; retstat=1; }
  fi


  #-----------------------------#
  # (4) README
  #-----------------------------#

  # if [ -f "$SR_SBREPO"/"$itemdir"/README ]; then
  #   [ "$(wc -L < "$SR_SBREPO"/"$itemdir"/README)" -le 79 ] || \
  #     log_warning -a "${itemid}: long lines in README"
  # fi

  if [ "$OPT_REPO" = 'SBo' ] && [ ! -f "$SR_SBREPO"/"$itemdir"/README ]; then
    { log_warning -a "${itemid}: README not found"; retstat=1; }
  fi

  [ "$retstat" = 0 ] && log_done
  return $retstat
}

#-------------------------------------------------------------------------------

function test_download
# Test whether download URLs are 404, by trying to pull the header
# $1 = itemid
# Return status:
# 0 = all good
# 1 = the test found something
# 2 = significant error
{
  local itemid="$1"
  local -a downlist
  local TMP_HEADER url curlstat
  local retstat=0

  downlist=( ${INFODOWNLIST[$itemid]} )
  if [ "${#downlist[@]}" != 0 ]; then
    log_normal -a "Testing download URLs ... "
    TMP_HEADER="$MYTMPDIR"/curlheader
    for url in "${downlist[@]}"; do
      # Try to retrieve just the header.
      > "$TMP_HEADER"
      case "$url" in
      *.googlecode.com/*)
        # Let's hear it for googlecode.com, HTTP HEAD support missing since 2008
        # https://code.google.com/p/support/issues/detail?id=660
        # "Don't be evil, but totally lame is fine"
        curl --connect-timeout 10 --retry 2 -q -f -s -k --ciphers ALL --disable-epsv --ftp-method nocwd -J -L -A slackrepo -o /dev/null "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" != 0 ]; then
          { log_warning -a "${itemid}: Download test failed: $(print_curl_status $curlstat). $url"; retstat=1; }
        fi
        ;;
      *)
        curl --connect-timeout 10 --retry 2 -f -v -k --ciphers ALL --disable-epsv --ftp-method nocwd -J -L -A slackrepo -I -o "$TMP_HEADER" "$url" >> "$ITEMLOG" 2>&1
        curlstat=$?
        if [ "$curlstat" = 0 ]; then
          remotelength=$(fromdos <"$TMP_HEADER" | grep 'Content-[Ll]ength: ' | tail -n 1 | sed 's/^.* //')
          # Proceed only if we seem to have extracted a valid content-length.
          if [ -n "$remotelength" ] && [ "$remotelength" != 0 ]; then
            # Filenames that have %nn encodings won't get checked.
            filename=$(fromdos <"$TMP_HEADER" | grep 'Content-[Dd]isposition:.*filename=' | sed -e 's/^.*filename=//' -e 's/^"//' -e 's/"$//' -e 's/\%20/ /g' -e 's/\%7E/~/g')
            # If no Content-Disposition, we'll have to guess:
            [ -z "$filename" ] && filename="$(basename "$url")"
            if [ -f "${SRCDIR[$itemid]}"/"$filename" ]; then
              cachedlength=$(stat -c '%s' "${SRCDIR[$itemid]}"/"$filename")
              if [ "$remotelength" != "$cachedlength" ]; then
                { log_warning -a "${itemid}: Source file $filename has been modified upstream."; retstat=1; }
              fi
            fi
          fi
        else
          # Header failed, try a full download (amazonaws is "special"... possibly more...)
          curl --connect-timeout 10 --retry 2 -q -f -s -k --ciphers ALL -J -L -A slackrepo -o "$MYTMPDIR"/curldownload "$url" >> "$ITEMLOG" 2>&1
          curlstat=$?
          if [ "$curlstat" = 0 ]; then
            remotemd5=$(md5sum <"$MYTMPDIR"/curldownload); remotemd5="${remotemd5/ */}"
            found='n'
            for cachedmd5 in ${INFOMD5LIST[$itemid]}; do
              if [ "$remotemd5" = "$cachedmd5" ]; then
                found='y'; break
              fi
            done
            if [ "$found" = 'n' ]; then
              log_warning -a "${itemid}: Source has apparently been modified upstream."
              log_info -a "$url"
              retstat=1
            fi
          else
            log_warning -a "${itemid}: Download test failed: $(print_curl_status $curlstat)."
            log_info -a "$url"
            retstat=1
            if [ -s "$TMP_HEADER" ]; then
              echo "The following headers may be informative:" >> "$ITEMLOG"
              cat "$TMP_HEADER" >> "$ITEMLOG"
            fi
          fi
          rm -f "$MYTMPDIR"/curldownload
        fi
        ;;
      esac
    done
    [ "$OPT_KEEP_TMP" != 'y' ] && rm -f "$TMP_HEADER"
  fi

  [ "$retstat" = 0 ] && log_done
  return $retstat
}

#-------------------------------------------------------------------------------

function test_package
# Test a package (check its name, and check its contents)
# $1 (optionally) -n => do not try to install the packages
# $1    = itemid
# $2... = paths of packages to be checked
# Return status:
# 0 = all good
# 1 = the test found something
# 2 = significant error
{
  local tryinstall='y'
  if [ "$1" = '-n' ]; then
    tryinstall='n'
    shift
  fi

  local itemid="$1"
  shift
  local itemprgnam="${ITEMPRGNAM[$itemid]}"
  local -a baddirlist
  local pkgpath pkgbasename filetype baddirlist baddir
  local retstat=0

  while [ $# != 0 ]; do
    pkgpath="$1"
    pkgbasename=$(basename "$pkgpath")
    shift
    log_normal -a "Testing package $pkgbasename ... "

    # check the prgnam
    parse_package_name "$pkgbasename"
    [ "$PN_PRGNAM" != "$itemprgnam" ] && \
      { log_warning -a "${itemid}: ${pkgbasename}: PRGNAM is \"$PN_PRGNAM\" (expected \"$itemprgnam\")"; retstat=1; }

    # check the version
    if [ "$CMD" = 'lint' ]; then
      # for the lint command, use the database (in case the package is out of date w.r.t. the .info file)
      checkversion=$(db_get_rev "$itemid" | cut -f2 -d" ")
    else
      # otherwise, it should be the same as INFOVERSION
      checkversion="${INFOVERSION[$itemid]}"
    fi
    [ "$PN_VERSION" != "${checkversion}" ] && [ "$PN_VERSION" != "${checkversion}_$(uname -r | tr - _)" ] && \
      { log_warning -a "${itemid}: ${pkgbasename}: VERSION is \"$PN_VERSION\" (expected \"${checkversion}\")"; retstat=1; }

    # check the arch
    okarch='n'
    if [ "$PN_ARCH" = "$SR_ARCH" ]; then
      okarch='y'
    else
      case "$PN_ARCH" in
        i386 | i486 | i586 | i686 )
          case "$SR_ARCH" in
            i386 | i486 | i586 | i686 ) okarch='y' ;;
          esac
          ;;
        arm )
          [ "${SR_ARCH:0:3}" = 'arm' ] && okarch='y'
          ;;
        arm* )
          [ "$SR_ARCH" = 'arm' ] && okarch='y'
          ;;
        noarch | fw )
          okarch='y'
          ;;
      esac
    fi
    [ "$okarch" != 'y' ] && { log_warning -a "${itemid}: ${pkgbasename}: ARCH is $PN_ARCH (expected $SR_ARCH)"; retstat=1; }

    # check the build
    [ -n "$SR_BUILD" ] && [ "$PN_BUILD" != "$SR_BUILD" ] && \
      { log_warning -a "${itemid}: ${pkgbasename}: BUILD is $PN_BUILD (expected $SR_BUILD)"; retstat=1; }

    # check the tag
    [ "$PN_TAG" != "$SR_TAG" ] && \
      { log_warning -a "${itemid}: ${pkgbasename}: TAG is \"$PN_TAG\" (expected \"$SR_TAG\")"; retstat=1; }

    # check the pkgtype
    [ "$PN_PKGTYPE" != "$SR_PKGTYPE" ] && \
      { log_warning -a "${itemid}: ${pkgbasename}: Package type is .$PN_PKGTYPE (expected .$SR_PKGTYPE)"; retstat=1; }

    # check that the actual compression type matches the suffix
    filetype=$(file -b "$pkgpath")
    case "$filetype" in
      'gzip compressed data'*)  [ "$PN_PKGTYPE" = 'tgz' ] || { log_warning -a "${itemid}: ${pkgbasename} has wrong suffix, should be .tgz"; retstat=1; } ;;
      'XZ compressed data'*)    [ "$PN_PKGTYPE" = 'txz' ] || { log_warning -a "${itemid}: ${pkgbasename} has wrong suffix, should be .txz"; retstat=1; } ;;
      'bzip2 compressed data'*) [ "$PN_PKGTYPE" = 'tbz' ] || { log_warning -a "${itemid}: ${pkgbasename} has wrong suffix, should be .tbz"; retstat=1; } ;;
      'LZMA compressed data'*)  [ "$PN_PKGTYPE" = 'tlz' ] || { log_warning -a "${itemid}: ${pkgbasename} has wrong suffix, should be .tlz"; retstat=1; } ;;
      *) log_error "${itemid}: ${pkgbasename} is \"$filetype\", not a package" ; return 2 ;;
    esac

    # list what's in the package (and check if it's really a tarball)
    # we'll reuse this file several times to analyse the contents
    TMP_PKGCONTENTS="$MYTMPDIR"/pkgcontents_"$pkgbasename"
    tar tvf "$pkgpath" > "$TMP_PKGCONTENTS" || { log_error -a "${itemid}: ${pkgbasename} is not a tar archive"; return 2; }

    # check where the files will be installed
    wrongstuff=$(awk \
      '$6!~/^(bin\/|boot\/|dev\/|etc\/|lib\/|lib64\/|opt\/|sbin\/|srv\/|usr\/|var\/|install\/|\.\/$)/ {printf "%s\n",$0}' <"$TMP_PKGCONTENTS")
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: ${pkgbasename} installs to unusual locations"
      log_info -a "$wrongstuff"
      retstat=1
    fi
    baddirlist=( 'usr/local/' 'usr/share/man/' )
    [ "$PN_ARCH"  = 'x86_64' ] && baddirlist+=( 'usr/lib/' ) # but not /lib (e.g. modules)
    [ "$PN_ARCH" != 'x86_64' ] && baddirlist+=( 'lib64/' 'usr/lib64/' )
    for baddir in "${baddirlist[@]}"; do
      wrongstuff=$(awk '$6~/^'"$(echo $baddir | sed s:/:'\\'/:g)"'/' <"$TMP_PKGCONTENTS")
      if [ -n "$wrongstuff" ]; then
        log_warning -a "${itemid}: $pkgbasename uses /$baddir"
        log_info -a "$wrongstuff"
        retstat=1
      fi
    done

    # check if it contains a slack-desc
    if ! grep -q ' install/slack-desc$' "$TMP_PKGCONTENTS"; then
      log_warning -a "${itemid}: ${pkgbasename} has no slack-desc"
      retstat=1
    fi

    # check top level directory
    topdir=$(head -n 1 "$TMP_PKGCONTENTS")
    if ! echo "$topdir" | grep -q '^drwxr-xr-x root/root .* \./$' ; then
      log_warning -a "${itemid}: ${pkgbasename} has a bad top level directory"
      log_info -a "$topdir"
      retstat=1
    fi

    # check groups and/or users
    okgroups='root'
    if [ -n "${VALID_GROUPS[$itemid]}" ]; then
      okgroups="(${okgroups}|${VALID_GROUPS[$itemid]})"
    fi
    okusers='root'
    if [ -n "${VALID_USERS[$itemid]}" ]; then
      okusers="(${okusers}|${VALID_USERS[$itemid]})"
    fi
    wrongstuff=$(awk \
      "\$2~/^$okusers\/$okgroups\$/ {next};
       \$2~/^[[:alpha:]]+\/[[:alpha:]]+\$/ {next};
       {printf \"%s\\n\",\$0}" <"$TMP_PKGCONTENTS")
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: ${pkgbasename} has files or dirs with unusual owner or group"
      log_info -a "$wrongstuff"
      retstat=1
    fi

    # check for uncompressed man pages (usr/share/man warning is handled above)
    wrongstuff=$(grep -E '^-.* usr/(share/)?man/' "$TMP_PKGCONTENTS" | grep -v '\.gz$')
    if [ -n "$wrongstuff" ]; then
      log_warning -a "${itemid}: ${pkgbasename} has uncompressed man pages"
      log_info -a "$wrongstuff"
      retstat=1
    fi

    [ "$retstat" = 0 ] && log_done

    # Note! Don't remove TMP_PKGCONTENTS yet, create_metadata will use it.

    # Install it to see what happens (but not if --dry-run)
    if [ "$OPT_DRY_RUN" != 'y' ] && [ "$tryinstall" != 'n' ]; then
      log_normal -a "Test installing $pkgbasename ..."
      install_packages "$pkgpath" || return 1
    fi

  done

  uninstall_packages "$itemid"
  return $retstat
}
