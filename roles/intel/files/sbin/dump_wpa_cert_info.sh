#!/bin/bash

#
# This tool reads the current WPA cert.pem certificate, prints its content,
# verifies it contains the SAN information and decodes it.
#
# Sample of successful output (only the SAN information):
#
#
#
# ./dump_wpa_cert_info.sh: =====================================================
# ./dump_wpa_cert_info.sh: /etc/wpa_supplicant/cert.pem SAN INFORMATION PRESENT
#  1783:d=5  hl=2 l=   3 prim:      OBJECT            :X509v3 Subject Alternative Name
#  1788:d=5  hl=3 l= 128 prim:      OCTET STRING      [HEX DUMP]:307EA07C060A2B060104018237140203A06E0C6C65794A6A6248567A64475679535751694F694A6A6248567A644756794D534973496D4E7364584E305A584A57626D6B694F6A45774D444573496E5A735957354E595842776157356E63794936657949784D4334794D7A49754F4441754D545578496A6F784E4441346658303D
# 
# ./dump_wpa_cert_info.sh: =====================================================
# ./dump_wpa_cert_info.sh: /etc/wpa_supplicant/cert.pem OCTECT STRING OFFSET 1788
# ./dump_wpa_cert_info.sh: /etc/wpa_supplicant/cert.pem OCTECT STRING HAS UNIVERSAL PRINCIPAL NAME
# ./dump_wpa_cert_info.sh: /etc/wpa_supplicant/cert.pem OCTECT STRING HAS UTF8STRING
#    18:d=3  hl=2 l= 108 prim: UTF8STRING        :eyJjbHVzdGVySWQiOiJjbHVzdGVyMSIsImNsdXN0ZXJWbmkiOjEwMDEsInZsYW5NYXBwaW5ncyI6eyIxMC4yMzIuODAuMTUxIjoxNDA4fX0=
# 
# ./dump_wpa_cert_info.sh: =====================================================
# ./dump_wpa_cert_info.sh: /etc/wpa_supplicant/cert.pem SAN INFORMATION FROM DECODED UTF8STRING
# 
# {"clusterId":"cluster1","clusterVni":1001,"vlanMappings":{"10.232.80.151":1408}}
# 
# 
#
#

CURRENT_CERT=/etc/wpa_supplicant/cert.pem
CERT_COPY=/tmp/$USER.$$.copy.cert.pem

echo $0: =====================================================
echo $0: dumping current $CURRENT_CERT for inspection
echo ''
echo ''
/bin/rm -f $CERT_COPY
cp $CURRENT_CERT $CERT_COPY

echo $0: =====================================================
echo $0: $CURRENT_CERT CERT FULL TEXT INFORMATION
openssl x509 -in $CERT_COPY -text
echo ''
echo ''

echo $0: =====================================================
echo $0: $CURRENT_CERT ASN.1 CERT SEQUENCE
openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -i
echo ''
echo ''

# 1782:d=5  hl=2 l=   3 prim:      OBJECT            :X509v3 Subject Alternative Name
# 1787:d=5  hl=3 l= 128 prim:      OCTET STRING      [HEX DUMP]:307EA07C060A2B060104018237140203A06E0C6C65794A6A6248567A64475679535751694F694A6A6248567A644756794D534973496D4E7364584E305A584A57626D6B694F6A45774D444573496E5A735957354E595842776157356E63794936657949784D4334794D7A49754F4441754D545578496A6F784E4441346658303D

echo $0: =====================================================
__san_info_present=`openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -i | grep 'X509v3 Subject Alternative Name'`
if [ "$__san_info_present" != "" ]
then
	echo $0: $CURRENT_CERT SAN INFORMATION PRESENT
	openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -i | grep -A1 'X509v3 Subject Alternative Name'
	echo ''
else
	echo $0: ERROR: $CURRENT_CERT SAN INFORMATION NOT PRESENT
	exit 1
fi

echo $0: =====================================================
__san_info_octect_string=`openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -i | grep -A1 'X509v3 Subject Alternative Name' | tail -1`
__octect_string_offset=0
if [ "$__san_info_octect_string" != "" ]
then
	__octect_string_offset=`echo $__san_info_octect_string | sed -e 's/:.*//'`
	echo $0: $CURRENT_CERT OCTECT STRING OFFSET $__octect_string_offset
else
	echo $0: ERROR: $CURRENT_CERT SAN INFORMATION DOES NOT CONTAIN OCTECT STRING
	exit 1
fi

#[opc@hpc-rackf1-01-ol75 wpa_supplicant]$ openssl x509 -in cert.pem -outform der | openssl asn1parse -inform der  -strparse 1787
#    0:d=0  hl=2 l= 126 cons: SEQUENCE          
#    2:d=1  hl=2 l= 124 cons: cont [ 0 ]        
#    4:d=2  hl=2 l=  10 prim: OBJECT            :Microsoft Universal Principal Name
#   16:d=2  hl=2 l= 110 cons: cont [ 0 ]        
#   18:d=3  hl=2 l= 108 prim: UTF8STRING        :eyJjbHVzdGVySWQiOiJjbHVzdGVyMSIsImNsdXN0ZXJWbmkiOjEwMDEsInZsYW5NYXBwaW5ncyI6eyIxMC4yMzIuODAuMTUxIjoxNDA4fX0=

__has_upn=`openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -strparse $__octect_string_offset | grep 'Universal Principal Name'`
if [ "$__has_upn" != "" ]
then
	echo $0: $CURRENT_CERT OCTECT STRING HAS UNIVERSAL PRINCIPAL NAME
else
	echo $0: ERROR: $CURRENT_CERT OCTECT STRING DOES NOT HAVE UNIVERSAL PRINCIPAL NAME
	exit 1
fi

__has_utf8string=`openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -strparse $__octect_string_offset | grep 'UTF8STRING '`
if [ "$__has_utf8string" != "" ]
then
	echo $0: $CURRENT_CERT OCTECT STRING HAS UTF8STRING
else
	echo $0: ERROR: $CURRENT_CERT OCTECT STRING DOES NOT HAVE UTF8STRING
	exit 1
fi

# 18:d=3 hl=2 l= 108 prim: UTF8STRING :eyJjbHVzdGVySWQiOiJjbHVzdGVyMSIsImNsdXN0ZXJWbmkiOjEwMDEsInZsYW5NYXBwaW5ncyI6eyIxMC4yMzIuODAuMTUxIjoxNDA4fX0=

openssl x509 -in $CERT_COPY -outform der | openssl asn1parse -inform der -strparse $__octect_string_offset | grep 'UTF8STRING'
echo ''

#echo eyJjbHVzdGVySWQiOiJjbHVzdGVyMSIsImNsdXN0ZXJWbmkiOjEwMDEsInZsYW5NYXBwaW5ncyI6eyIxMC4yMzIuODAuMTUxIjoxNDA4fX0= | base64 -d
#{"clusterId":"cluster1","clusterVni":1001,"vlanMappings":{"10.232.80.151":1408}}

echo $0: =====================================================
echo $0: $CURRENT_CERT SAN INFORMATION FROM DECODED UTF8STRING
__utf8string=`echo $__has_utf8string | sed -e 's/^.*UTF8STRING ://'`
echo ''
echo $__utf8string | base64 -d
echo ''
echo ''

exit 0
