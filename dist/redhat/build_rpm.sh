#!/bin/bash -e

. /etc/os-release
print_usage() {
    echo "build_rpm.sh --rebuild-dep --jobs 2"
    echo "  --rebuild-dep  rebuild dependency packages (CentOS)"
    echo "  --jobs  specify number of jobs"
    echo "  --dist  create a public distribution rpm"
    exit 1
}
REBUILD=0
JOBS=0
DIST=0
while [ $# -gt 0 ]; do
    case "$1" in
        "--rebuild-dep")
            REBUILD=1
            shift 1
            ;;
        "--jobs")
            JOBS=$2
            shift 2
            ;;
        "--dist")
            DIST=1
            shift 1
            ;;
        *)
            print_usage
            ;;
    esac
done

RPMBUILD=`pwd`/build/rpmbuild

if [ ! -e dist/redhat/build_rpm.sh ]; then
    echo "run build_rpm.sh in top of scylla dir"
    exit 1
fi

if [ "$ID" != "fedora" ] && [ "$ID" != "centos" ]; then
    echo "Unsupported distribution"
    exit 1
fi
if [ "$ID" = "fedora" ] && [ ! -f /usr/bin/mock ]; then
    sudo yum -y install mock
elif [ "$ID" = "centos" ] && [ ! -f /usr/bin/yum-builddep ]; then
    sudo yum -y install yum-utils
fi
if [ ! -f /usr/bin/git ]; then
    sudo yum -y install git
fi
if [ ! -f /usr/bin/rpmbuild ]; then
    sudo yum -y install rpm-build
fi
mkdir -p $RPMBUILD/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
if [ "$ID" = "centos" ]; then
    sudo yum install -y epel-release
    if [ $REBUILD = 1 ]; then
        ./dist/redhat/centos_dep/build_dependency.sh
    else
        sudo curl https://s3.amazonaws.com/downloads.scylladb.com/rpm/unstable/centos/master/latest/scylla.repo -o /etc/yum.repos.d/scylla.repo
    fi
fi
VERSION=$(./SCYLLA-VERSION-GEN)
SCYLLA_VERSION=$(cat build/SCYLLA-VERSION-FILE)
SCYLLA_RELEASE=$(cat build/SCYLLA-RELEASE-FILE)
echo $VERSION >version
./scripts/git-archive-all --extra version --force-submodules --prefix scylla-$SCYLLA_VERSION $RPMBUILD/SOURCES/scylla-$VERSION.tar
rm -f version
cp dist/redhat/scylla.spec.in $RPMBUILD/SPECS/scylla.spec
sed -i -e "s/@@VERSION@@/$SCYLLA_VERSION/g" $RPMBUILD/SPECS/scylla.spec
sed -i -e "s/@@RELEASE@@/$SCYLLA_RELEASE/g" $RPMBUILD/SPECS/scylla.spec

if [ $DIST -gt 0 ]; then
  sed -i -e "s/@@HOUSEKEEPING_CONF@@/true/g" $RPMBUILD/SPECS/scylla.spec
else
  sed -i -e "s/@@HOUSEKEEPING_CONF@@/false/g" $RPMBUILD/SPECS/scylla.spec
fi

if [ "$ID" = "fedora" ]; then
    if [ $JOBS -gt 0 ]; then
        rpmbuild -bs --define "_topdir $RPMBUILD" --define "_smp_mflags -j$JOBS" $RPMBUILD/SPECS/scylla.spec
    else
        rpmbuild -bs --define "_topdir $RPMBUILD" $RPMBUILD/SPECS/scylla.spec
    fi
    mock rebuild --resultdir=`pwd`/build/rpms $RPMBUILD/SRPMS/scylla-$VERSION*.src.rpm
else
    sudo yum-builddep -y  $RPMBUILD/SPECS/scylla.spec
    . /etc/profile.d/scylla.sh
    if [ $JOBS -gt 0 ]; then
        rpmbuild -ba --define "_topdir $RPMBUILD" --define "_smp_mflags -j$JOBS" $RPMBUILD/SPECS/scylla.spec
    else
        rpmbuild -ba --define "_topdir $RPMBUILD" $RPMBUILD/SPECS/scylla.spec
    fi
fi
