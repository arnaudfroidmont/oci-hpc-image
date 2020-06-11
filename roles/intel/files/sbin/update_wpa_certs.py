#!/usr/bin/python

#
#
# Copyright (C) 2018-2019 Fio Cattaneo <fio.cattaneo@oracle.com> <fio@cattaneo.us>, Oracle Corporation.
# Copyright (C) 2019 Marcin Zablocki <marcin.zablocki@oracle.com>, Oracle Corporation.
#
# This file is distributed under the GPL Version 2 Licence.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; Version 2 of the License.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# GPL Version 2: https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html
#
#

#
#
# FIXME: trim out debug messages once we know it works
# FIXME: remove legacy code when we no longer need it
#
#

import json
import os
import sys
import fcntl
import socket
import time
import fcntl
import logging.handlers
import syslog
import random
import subprocess
import shutil
import tempfile
import filecmp
from OpenSSL import crypto

PROGRAM_NAME = "update_wpa_certs.py"
RAND_DELAY = 120
DOWNLOAD_URL = "http://169.254.169.254/opc/v1"
IDENTITY_DOWNLOAD_URL = DOWNLOAD_URL + "/identity/"
INSTANCE_DOWNLOAD_URL = DOWNLOAD_URL + "/instance/"
CERT_BUNDLE_PFX_PASSPHRASE="hic sunt leones"
WPA_SUPPLICANT_DIR = "/etc/wpa_supplicant"
WPA_SUPPLICANT_CONF_FILE = WPA_SUPPLICANT_DIR + "/wpa_supplicant.conf"
WPA_SUPPLICANT_BUNDLE_FILE_PFX = WPA_SUPPLICANT_DIR + "/certs_bundle.pfx"
WPA_SUPPLICANT_LOCKFILE = WPA_SUPPLICANT_DIR + "/.update_wpa_certs_lockfile"
WPA_SUPPLICANT_IDENTITY_BLOB = WPA_SUPPLICANT_DIR + "/oci_identity_blob.json"
WPA_SUPPLICANT_INSTANCE_BLOB = WPA_SUPPLICANT_DIR + "/oci_instance_blob.json"
WPA_AUTH_DELAY = 10
NETWORK_INTERFACE = "enp94s0f0"


#
# FIXME: should make all of this into a class.
#

global_fd = -1

#
# fixup selinux attributes
#
def fixup_selinux_attributes(filename):
	cmd = "/usr/bin/chcon system_u:object_r:etc_t:s0 " + filename
	status = subprocess.Popen(cmd, shell=True).wait()
	if status != 0:
		syslog.syslog(syslog.LOG_ERR, "ERROR setting up selinux attributes: " + cmd + ": " + str(status))
		exit(18)
	# FIXME: remove this debug print
	syslog.syslog(syslog.LOG_INFO, "selinux attributes have been set: " + cmd)

def check_has_ip_address():
	cmd = "/usr/sbin/ifconfig " + NETWORK_INTERFACE + " | grep 'inet ' | awk '{ print $2; }'"
	p = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
	status = p.wait()
	if status != 0:
		syslog.syslog(syslog.LOG_ERR, "cannot retrieve IP address for " + NETWORK_INTERFACE)
		exit(1)
	output_s = p.stdout.read()
	output_s = output_s.rstrip('\n')
	if output_s == '':
		syslog.syslog(syslog.LOG_WARNING, "interface " + NETWORK_INTERFACE + " has no IP address, nothing to do")
		exit(0)
	# FIXME: remove this debug print
	syslog.syslog(syslog.LOG_INFO, "interface " + NETWORK_INTERFACE + " has IP address " + output_s)

def startup_check_and_lock(nodelay):
	if os.getuid() != 0:
		syslog.syslog(syslog.LOG_ERR, "ERROR: must be root")
		exit(1)
	if not os.path.exists(WPA_SUPPLICANT_DIR):
		syslog.syslog(syslog.LOG_ERR, "ERROR: " + WPA_SUPPLICANT_DIR + " directory does not exist")
		exit(2)
	try:
		if not os.path.exists(WPA_SUPPLICANT_LOCKFILE):
			os.close(os.open(WPA_SUPPLICANT_LOCKFILE, os.O_CREAT | os.O_TRUNC, 0400))
			fixup_selinux_attributes(WPA_SUPPLICANT_LOCKFILE)
	except:
		syslog.syslog(syslog.LOG_ERR, "cannot create lockfile " + WPA_SUPPLICANT_LOCKFILE)
		exit(3)
	global_fd = os.open(WPA_SUPPLICANT_LOCKFILE, os.O_RDONLY)
	try:
		fcntl.flock(global_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
		syslog.syslog(syslog.LOG_ERR, PROGRAM_NAME + " instance locked (self pid = " + str(os.getpid()) + ")")
	except:
		syslog.syslog(syslog.LOG_WARNING, PROGRAM_NAME + " is already running (self pid = " + str(os.getpid()) + ")")
		exit(0)
	if nodelay:
		syslog.syslog(syslog.LOG_INFO, "starting with zero delay")
	else:
		delay = random.randint(1, RAND_DELAY)
		syslog.syslog(syslog.LOG_INFO, "starting with a random delay of " + str(delay) + " seconds")
		time.sleep(delay)

#
# get metadata from url_path, save download to oci_json_blob for debug purposes
#
def get_oci_metadata(url_path, oci_json_blob):
	p = subprocess.Popen("/usr/bin/curl -s -f -q " + url_path, stdout=subprocess.PIPE, shell=True)
	status = p.wait()
	if status != 0:
		syslog.syslog(syslog.LOG_ERR, "cannot retrieve OCI metadata from " + url_path + ": status: " + str(status))
		return None
	try:
		output_s = p.stdout.read()
		output_json = json.loads(output_s)
	except:
		syslog.syslog(syslog.LOG_ERR, "malformed JSON OCI metadata: " + url_path)
		return None
	try:
		fd = os.open(oci_json_blob, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0644)
		os.write(fd, str(output_json))
		os.close(fd)
		fixup_selinux_attributes(oci_json_blob)
	except:
		# this can never happen
		syslog.syslog(syslog.LOG_ERR, "cannot write: " + oci_json_blob)
		exit(7)
	return output_json

#
# call the above, with retries
#
def download_oci_blob(url_path, oci_json_blob):
	for retry in range(3):
		oci_blob = get_oci_metadata(url_path, oci_json_blob)
		if oci_blob is not None:
			syslog.syslog(syslog.LOG_INFO, "downloaded OCI JSON blob from " + url_path)
			return oci_blob
		syslog.syslog(syslog.LOG_WARNING, "cannot download oci blob " + url_path + ": retrying")
		os.sleep(10)
	#
	# too many retries, give up
	#
	syslog.syslog(syslog.LOG_ERR, "cannot download oci blob " + url_path + " (too many retries): giving up")
	exit(5)

#
# create WPA config file if it does not exist, or if info has changed.
# instance id is idempotent, but FQDN can be changed.
#
def create_wpa_config(instance):
	temp_wpa_conf = tempfile.TemporaryFile()
	template = '''#
#
# This file is autogenerated by update_wpa_certs.py. Do not modify.
#
# {wpasupplicantconffile}
#
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=wheel
#
network={{
        fragment_size=1024
        key_mgmt=IEEE8021X
        eap=TLS
        private_key_passwd="{passphrase}"
        private_key="{certsbundlepfx}"
        identity="{fqdn}-{id}"
        eapol_flags=0
}}
'''

	context = {
		"passphrase" : CERT_BUNDLE_PFX_PASSPHRASE,
		"wpasupplicantconffile" : WPA_SUPPLICANT_CONF_FILE,
		"certsbundlepfx" : WPA_SUPPLICANT_BUNDLE_FILE_PFX,
		"wpasupplicantdir" : WPA_SUPPLICANT_DIR,
		"fqdn" : instance["node_fqdn"],
		"id" : instance["id"]
	}

	#
	# none of this is expected to fail
	#
	try:
		fd = os.open(temp_wpa_conf.name, os.O_CREAT | os.O_WRONLY | os.O_TRUNC, 0644)
		os.write(fd, template.format(**context))
		if not os.path.exists(WPA_SUPPLICANT_CONF_FILE):
			syslog.syslog(syslog.LOG_INFO, WPA_SUPPLICANT_CONF_FILE + ": configuration does not exist, creating")
			os.rename(temp_wpa_conf.name, WPA_SUPPLICANT_CONF_FILE)
			fixup_selinux_attributes(WPA_SUPPLICANT_CONF_FILE)
			return True
		if not filecmp.cmp(WPA_SUPPLICANT_CONF_FILE, temp_wpa_conf.name):
			syslog.syslog(syslog.LOG_INFO, WPA_SUPPLICANT_CONF_FILE + ": configuration has been updated, updating")
			os.rename(temp_wpa_conf.name, WPA_SUPPLICANT_CONF_FILE)
			fixup_selinux_attributes(WPA_SUPPLICANT_CONF_FILE)
			return True
		else:
			syslog.syslog(syslog.LOG_INFO, WPA_SUPPLICANT_CONF_FILE + ": configuration is unchanged")
			os.remove(temp_wpa_conf.name)
			return False
	except:
		syslog.syslog(syslog.LOG_ERR, "ERROR: cannot update " + WPA_SUPPLICANT_CONF_FILE)
		exit(15)

#
# legacy support.
# needed by /opt/oci-hpc/sbin/dump_wpa_cert_info.sh which dumps the VLAN Identifiers.
# will remove this once it has been converted to native python code.
#
def legacy_update_certs(identity):
	syslog.syslog(syslog.LOG_WARNING, "writing individual certificates (cert.pem,key.pem,intermediate.pem) for legacy support")
	with open(WPA_SUPPLICANT_DIR + "/cert.pem", "w") as text_file:
		text_file.write(identity["cert.pem"])
	fixup_selinux_attributes(WPA_SUPPLICANT_DIR + "/cert.pem")
	with open(WPA_SUPPLICANT_DIR + "/key.pem", "w") as text_file:
		text_file.write(identity["key.pem"])
	fixup_selinux_attributes(WPA_SUPPLICANT_DIR + "/key.pem")
	with open(WPA_SUPPLICANT_DIR + "/intermediate.pem", "w") as text_file:
		text_file.write(identity["intermediate.pem"])
	fixup_selinux_attributes(WPA_SUPPLICANT_DIR + "/intermediate.pem")
	if os.path.exists(WPA_SUPPLICANT_DIR + "/pki_blob.json"):
		os.remove(WPA_SUPPLICANT_DIR + "/pki_blob.json")

#
# format OpenSSL timestamp format.
# sample valid string: 20190404022612Z
# converts to: 2019-04-04T02:26:12Z
#
def ssl_ts(s):
	if len(s) != 15:
		return s
	return s[0:4] + "-" + s[4:6] + "-" + s[6:8] + "T" + s[8:10] + ":" + s[10:12] + ":" + s[12:14] + "Z";

def not_before_ts(cert):
	return ssl_ts(cert.get_notBefore())

def not_after_ts(cert):
	return ssl_ts(cert.get_notAfter())

#
#def dump_validity(validity):
#	cmd = "openssl x509 -in " + TEMP_DIR + "/cert.pem -text | grep -A2 Validity | grep \"" + validity + "\""
#	p = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
#	p.wait()
#	s = p.stdout.read()
#	syslog.syslog(syslog.LOG_INFO, "cert validity: " + s.lstrip())
#

def create_pfx_bundle(identity):
	intermediate = crypto.load_certificate(crypto.FILETYPE_PEM, identity['intermediate.pem'])
	cert = crypto.load_certificate(crypto.FILETYPE_PEM, identity['cert.pem'])
	key = crypto.load_privatekey(crypto.FILETYPE_PEM, identity['key.pem'], CERT_BUNDLE_PFX_PASSPHRASE)
	write_pfx_bundle = False
	if os.path.exists(WPA_SUPPLICANT_BUNDLE_FILE_PFX):
		with open(WPA_SUPPLICANT_BUNDLE_FILE_PFX, "r") as bundle_file:
			e_cert = crypto.load_pkcs12(bundle_file.read(), CERT_BUNDLE_PFX_PASSPHRASE).get_certificate()
		syslog.syslog(syslog.LOG_INFO, "current PFX bundle: valid from " + not_before_ts(e_cert) + ", valid until " + not_after_ts(e_cert))
		if (e_cert.get_notAfter() == cert.get_notAfter()):
			syslog.syslog(syslog.LOG_INFO, "new PFX bundle: valid from " + not_before_ts(cert) + ", valid until " + not_after_ts(cert) + ": unchanged")
		else:
			syslog.syslog(syslog.LOG_INFO, "new PFX bundle: valid from " + not_before_ts(cert) + ", valid until " + not_after_ts(cert) + ": updating")
			write_pfx_bundle = True
	else:
		syslog.syslog(syslog.LOG_INFO, "PFX bundle: valid from " + not_before_ts(cert) + ", valid until " + not_after_ts(cert) + ": creating")
		write_pfx_bundle = True
	if write_pfx_bundle:
		cacerts = []
		cacerts.append(intermediate)
		#
		# handle different method names of OpenSSL.crypto module.
		#
		try:
			pkcs12 = crypto.PKCS12Type()
			syslog.syslog(syslog.LOG_INFO, "crypto.PKCS12Type() = " + str(pkcs12))
		except:
			pkcs12 = crypto.PKCS12()
			syslog.syslog(syslog.LOG_INFO, "crypto.PKCS12() = " + str(pkcs12))
		pkcs12.set_ca_certificates(cacerts)
		pkcs12.set_certificate(cert)
		pkcs12.set_privatekey(key)
		with open(WPA_SUPPLICANT_BUNDLE_FILE_PFX, "w") as bundle_file:
			bundle_file.write(pkcs12.export(passphrase=CERT_BUNDLE_PFX_PASSPHRASE))
			# FIXME: remove this
			syslog.syslog(syslog.LOG_INFO, "updated PFX bundle: valid from " + not_before_ts(cert) + ", valid until " + not_after_ts(cert))
		fixup_selinux_attributes(WPA_SUPPLICANT_BUNDLE_FILE_PFX)
		return True
	else:
		return False

def restart_wpa_supplicant():
	status = subprocess.Popen("/usr/bin/systemctl enable wpa_supplicant", shell=True).wait()
	if status != 0:
		syslog.syslog(syslog.LOG_ERR, "ERROR enabling wpa_supplicant service, status: " + str(status))
		exit(17)
	status = subprocess.Popen("/usr/bin/systemctl restart wpa_supplicant", shell=True).wait()
	if status != 0:
		syslog.syslog(syslog.LOG_ERR, "ERROR restarting wpa_supplicant service, status: " + str(status))
		exit(18)

def reload_or_restart_wpa_supplicant(unix_timestamp, wpa_config_updated, pfx_bundle_updated, nodelay):
	if wpa_config_updated:
		#
		# restart wpa_supplicant daemon as config has changed.
		#
		syslog.syslog(syslog.LOG_INFO, "wpa_supplicant configuration has changed: restarting @ UNIX timestamp " + str(unix_timestamp))
		restart_wpa_supplicant()
		return True
	if pfx_bundle_updated or nodelay:
		#
		# load wpa_supplicant config by sending SIGHUP to wpa_supplicant daemon.
		# restarting the service is not good because it generates an ETH link-up event.
		#
		syslog.syslog(syslog.LOG_INFO, "reloading wpa_supplicant configuration @ UNIX timestamp " + str(unix_timestamp))
		status = subprocess.Popen("killall -HUP wpa_supplicant", shell=True).wait()
		if status != 0:
			syslog.syslog(syslog.LOG_WARNING, "WARNING: cannot send SIGHUP to wpa_supplicant daemon, trying to restart")
			restart_wpa_supplicant()
		return True
	syslog.syslog(syslog.LOG_INFO, "neither WPA configuration nor PFX bundle have changed, no need to reload or restart wpa_supplicant")
	return False

#
# if event_expected and not_found:
#	dump_error("ERROR: event not found " + event")
# if event_expected == False and found:
#	dump_error("ERROR: event found " + event")
#
#
def dump_wpa_supplicant_status(unix_timestamp, event, event_expected):
	#syslog.syslog(syslog.LOG_INFO, "looking for event '" + event + "' after timestamp " + str(unix_timestamp))
	cmd = "tail -20 /var/log/wpa_supplicant.log | grep " + event
	p = subprocess.Popen(cmd, stdout=subprocess.PIPE, shell=True)
	p.wait()
	event_found = False
	event_s_found = None
	#
	# WPA supplicant log file uses raw UNIX timestamps
	# example:
	#         1552676165.346846: enp94s0f0: CTRL-EVENT-EAP-SUCCESS EAP authentication completed successfully
	#
	for s in p.stdout:
		s = s.lstrip()
		if len(s) < len(str(unix_timestamp)):
			continue
		s_ts = int(s[0:len(str(unix_timestamp))])
		#syslog.syslog(syslog.LOG_INFO, "unix_timestamp = " + str(unix_timestamp) + ": " + str(s_ts))
		if s_ts >= unix_timestamp:
			event_found = True
			event_s_found = s
	if event_found and event_expected:
		#
		# EVENT was found and was expected
		#
		syslog.syslog(syslog.LOG_INFO, event_s_found)
	if not event_found and event_expected:
		#
		# EVENT was not found and was expected
		#
		syslog.syslog(syslog.LOG_ERR, "ERROR: cannot find WPA event '" + event + "' at or after timestamp " + str(unix_timestamp) + ": check /var/log/wpa_supplicant.log for more information")
	if event_found and not event_expected:
		#
		# EVENT was found and was not expected
		#
		syslog.syslog(syslog.LOG_ERR, "ERROR: found unexpected WPA event '" + event + "' at or after timestamp " + str(unix_timestamp) + ": check /var/log/wpa_supplicant.log for more information")


#
#
# main code
#
#
def __main(nodelay):
	#
	# check if there is an IP address
	#
	check_has_ip_address()
	#
	# startup checks and lock process (only one instance can be running)
	#
	startup_check_and_lock(nodelay)
	identity = download_oci_blob(IDENTITY_DOWNLOAD_URL, WPA_SUPPLICANT_IDENTITY_BLOB)
	instance = download_oci_blob(INSTANCE_DOWNLOAD_URL, WPA_SUPPLICANT_INSTANCE_BLOB)
	#
	# augment instance info with node_fdqn
	#
	instance["node_fqdn"] = socket.getfqdn()
	#
	# dump for debug as well as to verify content
	#
	try:
		syslog.syslog(syslog.LOG_INFO, "cert.pem = " + identity["cert.pem"][:100] + ".......")
		syslog.syslog(syslog.LOG_INFO, "key.pem = " + identity["key.pem"][:100] + ".......")
		syslog.syslog(syslog.LOG_INFO, "intermediate.pem = " + identity["intermediate.pem"][:100] + ".......")
		syslog.syslog(syslog.LOG_INFO, "instance_id = " + instance["id"])
		syslog.syslog(syslog.LOG_INFO, "instance_node_fqdn = " + instance["node_fqdn"])
	except:
		syslog.syslog(syslog.LOG_ERR, "ERROR: cannot find expected content in OCI JSON blobs")
		exit(18)
	#
	# create or update wpa config if it doesn't exist
	#
	wpa_config_updated = create_wpa_config(instance)
	# FIXME: remove this debug log
	syslog.syslog(syslog.LOG_INFO, "wpa_config_updated = " + str(wpa_config_updated))
	#
	# legacy support.
	# needed by /opt/oci-hpc/sbin/dump_wpa_cert_info.sh which dumps the VLAN Identifiers.
	# will remove this once it has been converted to native python code.
	#
	legacy_update_certs(identity)
	#
	# create or update PFX bundle
	#
	pfx_bundle_updated = create_pfx_bundle(identity)
	# FIXME: remove this debug log
	syslog.syslog(syslog.LOG_INFO, "pfx_bundle_updated = " + str(pfx_bundle_updated))
	#
	# reload configuration
	#
	unix_timestamp = int(time.time())
	# FIXME: remove this debug log
	syslog.syslog(syslog.LOG_INFO, "nodelay = " + str(nodelay))
	reloaded = reload_or_restart_wpa_supplicant(unix_timestamp, wpa_config_updated, pfx_bundle_updated, nodelay)
	if reloaded:
		#
		# update is asynchronous, so give some time for that to occur
		#
		time.sleep(WPA_AUTH_DELAY)
		dump_wpa_supplicant_status(unix_timestamp, "CTRL-EVENT-EAP-STARTED", True)
		dump_wpa_supplicant_status(unix_timestamp, "CTRL-EVENT-EAP-SUCCESS", True)
		dump_wpa_supplicant_status(unix_timestamp, "CTRL-EVENT-CONNECTED", True)
		dump_wpa_supplicant_status(unix_timestamp, "FAIL", False)

def main():
	nodelay = False
	if (len(sys.argv) > 1) and (sys.argv[1] == "nodelay"):
		nodelay = True
	try:
		__main(nodelay)
		exit(0)
	except Exception as e:
		syslog.syslog(syslog.LOG_ERR, "ERROR: unhandled exception: " + str(e))
		exit(99)



#
# call main
#
main()
