#!/bin/bash

#=================================================
# COMMON VARIABLES
#=================================================

# dependencies used by the app
pkg_dependencies="postgresql libjemalloc-dev ruby-dev zlib1g zlib1g-dev libssl-dev libyaml-dev libcurl4-openssl-dev libpq-dev build-essential libapr1-dev libxslt1-dev libxml2-dev imagemagick libmagickwand-dev"

RUBY_VERSION="2.6.6"

BUNDLER_VERSION="2.2.3"

#=================================================
# PERSONAL HELPERS
#=================================================

#=================================================
# EXPERIMENTAL HELPERS
#=================================================


#=================================================
# FUTURE OFFICIAL HELPERS
#=================================================


#!/bin/bash

# Need also the helper https://github.com/YunoHost-Apps/Experimental_helpers/blob/master/ynh_handle_getopts_args/ynh_handle_getopts_args

rbenv_install_dir="/opt/rbenv"
# RBENV_ROOT is the directory of rbenv, it needs to be loaded as a environment variable.
export RBENV_ROOT="$rbenv_install_dir"

# Install ruby version management
#
# [internal]
#
# usage: ynh_install_rbenv
ynh_install_rbenv () {
  echo "Installation of rbenv - ruby version management" >&2
  # Build an app.src for rbenv
  mkdir -p "../conf"
  echo "SOURCE_URL=https://github.com/rbenv/rbenv/archive/v1.1.2.tar.gz
SOURCE_SUM=80ad89ffe04c0b481503bd375f05c212bbc7d44ef5f5e649e0acdf25eba86736" > "../conf/rbenv.src"
  # Download and extract rbenv
  ynh_setup_source "$rbenv_install_dir" rbenv

  # Build an app.src for ruby-build
  mkdir -p "../conf"
  echo "SOURCE_URL=https://github.com/rbenv/ruby-build/archive/v20200520.tar.gz
SOURCE_SUM=52be6908a94fbd4a94f5064e8b19d4a3baa4b773269c3884165518d83bcc8922" > "../conf/ruby-build.src"
  # Download and extract ruby-build
  ynh_setup_source "$rbenv_install_dir/plugins/ruby-build" ruby-build

  (cd $rbenv_install_dir
  ./src/configure && make -C src)

# Create shims directory if needed
if [ ! -d $rbenv_install_dir/shims ] ; then
  mkdir $rbenv_install_dir/shims
fi
}

# Install a specific version of ruby
#
# ynh_install_ruby will install the version of ruby provided as argument by using rbenv.
#
# rbenv (ruby version management) stores the target ruby version in a .ruby_version file created in the target folder (using rbenv local <version>)
# It then uses that information for every ruby user that uses rbenv provided ruby command
#
# This helper creates a /etc/profile.d/rbenv.sh that configures PATH environment for rbenv
# for every LOGIN user, hence your user must have a defined shell (as opposed to /usr/sbin/nologin)
#
# Don't forget to execute ruby-dependent command in a login environment
# (e.g. sudo --login option)
# When not possible (e.g. in systemd service definition), please use direct path
# to rbenv shims (e.g. $RBENV_ROOT/shims/bundle)
#
# usage: ynh_install_ruby ruby_version user
# | arg: -v, --ruby_version= - Version of ruby to install.
#        If possible, prefer to use major version number (e.g. 8 instead of 8.10.0).
#        The crontab will handle the update of minor versions when needed.
ynh_install_ruby () {
  # Declare an array to define the options of this helper.
  declare -Ar args_array=( [v]=ruby_version= )
  # Use rbenv, https://github.com/rbenv/rbenv to manage the ruby versions
  local ruby_version
  # Manage arguments with getopts
  ynh_handle_getopts_args "$@"

  # Create $rbenv_install_dir
  mkdir -p "$rbenv_install_dir/plugins/ruby-build"

  # Load rbenv path in PATH
  CLEAR_PATH="$rbenv_install_dir/bin:$PATH"

  # Remove /usr/local/bin in PATH in case of ruby prior installation
  PATH=$(echo $CLEAR_PATH | sed 's@/usr/local/bin:@@')

  # Move an existing ruby binary, to avoid to block rbenv
  test -x /usr/bin/ruby && mv /usr/bin/ruby /usr/bin/ruby_rbenv

  # If rbenv is not previously setup, install it
  if ! type rbenv > /dev/null 2>&1
  then
    ynh_install_rbenv
  elif dpkg --compare-versions "$($rbenv_install_dir/bin/rbenv --version | cut -d" " -f2)" lt "1.1.2"
  then
    ynh_install_rbenv
  elif dpkg --compare-versions "$($rbenv_install_dir/plugins/ruby-build/bin/ruby-build --version | cut -d" " -f2)" lt "20200520"
  then
    ynh_install_rbenv
  fi

  # Restore /usr/local/bin in PATH (if needed)
  PATH=$CLEAR_PATH

  # And replace the old ruby binary
  test -x /usr/bin/ruby_rbenv && mv /usr/bin/ruby_rbenv /usr/bin/ruby

  # Install the requested version of ruby
  CONFIGURE_OPTS="--disable-install-doc --with-jemalloc" MAKE_OPTS="-j2" rbenv install --skip-existing $ruby_version

  # Store the ID of this app and the version of ruby requested for it
  echo "$YNH_APP_ID:$ruby_version" | tee --append "$rbenv_install_dir/ynh_app_version"

  # Store ruby_version into the config of this app
  ynh_app_setting_set $app ruby_version $ruby_version

  # Set environment for ruby users
  echo  "#rbenv
export RBENV_ROOT=$rbenv_install_dir
export PATH=\"$rbenv_install_dir/bin:$PATH\"
eval \"\$(rbenv init -)\"
#rbenv" > /etc/profile.d/rbenv.sh

  # Load the right environment for the Installation
  eval "$(rbenv init -)"

  (cd $final_path
  rbenv local $ruby_version)
}

# Remove the version of ruby used by the app.
#
# This helper will check if another app uses the same version of ruby,
# if not, this version of ruby will be removed.
# If no other app uses ruby, rbenv will be also removed.
#
# usage: ynh_remove_ruby
ynh_remove_ruby () {
  ruby_version=$(ynh_app_setting_get $app ruby_version)

  # Remove the line for this app
  sed --in-place "/$YNH_APP_ID:$ruby_version/d" "$rbenv_install_dir/ynh_app_version"

  # If no other app uses this version of ruby, remove it.
  if ! grep --quiet "$ruby_version" "$rbenv_install_dir/ynh_app_version"
  then
    $rbenv_install_dir/bin/rbenv uninstall --force $ruby_version
  fi

  # Remove rbenv environment configuration
  rm /etc/profile.d/rbenv.sh

  # If no other app uses rbenv, remove rbenv and dedicated group
  if [ ! -s "$rbenv_install_dir/ynh_app_version" ]
  then
    ynh_secure_remove "$rbenv_install_dir"
  fi
}