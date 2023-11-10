#!/usr/bin/python3

import os
import sys
import configparser
import pprint
import socket
import ldap
import subprocess

DEBUG = False
DEBUG_LDAP = False
CONFIG_PATH = "/root/wiregate/"
LOCAL_DB_PATH = '/etc/wireguard/clients/'

# parse config
cds = 'wiregate' #ConfigParser dummy section
with open(CONFIG_PATH + '/config', 'r') as f:
    config_string = '[' + cds + ']\n' + f.read()
    config = configparser.ConfigParser()
    config.read_string(config_string)

baseDN = config.get(cds, 'ldap_basedn')
LDAP_SERVER = config.get(cds, 'ldap_server')
LDAP_LOGIN = config.get(cds, 'ldap_login') + ',' + baseDN
LDAP_PASSWORD = config.get(cds, 'ldap_password')

serverhost = socket.gethostname()
searchScope = ldap.SCOPE_SUBTREE

def LdapQuery(searchFilter, searchAttrs):
    ldap.set_option(ldap.OPT_X_TLS_REQUIRE_CERT, ldap.OPT_X_TLS_NEVER)

    if DEBUG_LDAP: 
        print("Connecting to " + LDAP_SERVER)
    l = ldap.initialize(LDAP_SERVER)
    try:
        #l.set_option(ldap.OPT_REFERRALS, 0)
        #l.set_option(ldap.OPT_PROTOCOL_VERSION, 3)
        #l.set_option(ldap.OPT_X_TLS, ldap.OPT_X_TLS_DEMAND)
        #l.set_option(ldap.OPT_X_TLS_DEMAND, True)
        #l.set_option(ldap.OPT_DEBUG_LEVEL, 255)
        l.set_option(ldap.OPT_NETWORK_TIMEOUT, 10.0)
        l.simple_bind_s(LDAP_LOGIN, LDAP_PASSWORD)

        query = {}
        ldap_result_id = l.search(baseDN, searchScope, searchFilter, searchAttrs)
        while 1:
            rType, rData = l.result(ldap_result_id, 0)
            if (rData == []):
                break
            else:
                if rType == ldap.RES_SEARCH_ENTRY:
                    cn = rData[0][0]
                    data = rData[0][1]

                    #Flatten, just for more easy access
                    for (k, v) in data.items():
                        if len(v) == 1:
                            data[k] = v[0]

                    #uid = data["uid"]
                    query[cn] = data
        return query 

    except ldap.LDAPError as e:
        print(e)
        sys.exit(2)

    finally:
        if DEBUG_LDAP: 
            print('Server unbind.')
        l.unbind_s()
    return 0

def main():
    print("] WireGate LDAP sync")

    # query ldap server and gather list of REMOTE peers which belong to cn=<HOSTNAME>,ou=Groups,baseDN
    ldapGroups = LdapQuery('(|(&(objectClass=groupOfUniqueNames)(cn=' + serverhost + ')))', ['uniqueMember'])

    if ldapGroups == {}:
        print('] Group ' + serverhost + ' not found')
        sys.exit(1)
 
    if ldapGroups != 0:
        members = ldapGroups['cn=' + serverhost + ',ou=Groups,' + baseDN]['uniqueMember']
        if not isinstance(members, list):
            members = [members]
        print('] Group: ' + serverhost)
        print('] Remote members: ' + str(len(members)))

        remote_peers = []
        for member in members:
            d_member = member.decode('ascii')
            if DEBUG:
                print('] Processing ' + str(d_member))
 
            searchFilterUser='(' + d_member.split(',')[0] + ')'
            ldapUser = LdapQuery(searchFilterUser, ['mail', 'l'])
            user = ldapUser[d_member]
            #get attributes
            #mail
            m_mail = str(user['mail'].decode('ascii'))
            m_domain = m_mail.split('@')[1]
            m_user = m_mail.split('@')[0]

            m_peername = m_domain + '-' + m_user

            #get additional peers provided with the l attribute
            if 'l' in user:
                labels = user['l']
                if not isinstance(labels, list):
                    labels = [labels]
                for label in labels:
                    peer = m_peername + '-' + str(label.decode('ascii'))
                    remote_peers.append({ 'mail': m_mail, 'peer': peer })

            #get the parent peer
            peer = m_peername
            remote_peers.append({ 'mail': m_mail, 'peer': peer })

            #searchFilterUserSubs='(|(&(objectClass=*)(member=uid=%s,cn=users,ou=Groups,' + baseDN + ')))'
            user_subscriptions= LdapQuery('(|(&(objectClass=groupOfUniqueNames)(uniqueMember=' + str(d_member) + ')))', ['cn'])
            if DEBUG:
                pp = pprint.PrettyPrinter(depth=3)
                pp.pprint(user_subscriptions)

    print("] Remote peers: " + str(len(remote_peers)))
    if DEBUG:
        pp = pprint.PrettyPrinter(depth=3)
        pp.pprint(remote_peers)

    # query LOCAL peers database
    local_peers = []
    for file in os.listdir(LOCAL_DB_PATH):
        if file.endswith(".info"):
            try:
                cds = 'localdata' #ConfigParser dummy section
                with open(LOCAL_DB_PATH + '/' + file, 'r') as f:
                    data_string = '[' + cds + ']\n' + f.read()
                    local_peer_data = configparser.ConfigParser()
                    local_peer_data.read_string(data_string)
                local_mail = local_peer_data.get(cds, 'email')
                local_peer = local_peer_data.get(cds, 'peer')
                local_peers.append({ 'mail': local_mail, 'peer': local_peer })
        
            except Exception as e:
                print(e)
                sys.exit(2)

    print("] Local peers: " + str(len(local_peers)))
    if DEBUG:
        pp = pprint.PrettyPrinter(depth=3)
        pp.pprint(local_peers)

    # add / enable REMOTE peers if they DO NOT exist in the local database
    for r_peer in remote_peers:
        #print('add peer ' + r_peer['peer'] + ' - ' + r_peer['mail'])
        process = subprocess.Popen([CONFIG_PATH + "peer_add.sh", "-p", r_peer['peer'], "-e", r_peer['mail']])
        process.wait()

    # disable (do not remove) LOCAL peers which DO NOT exist in the remote database
    for l_peer in local_peers:
        if l_peer not in remote_peers:
            #print('rem peer ' + l_peer['peer'] + ' - ' + l_peer['mail'])
            process = subprocess.Popen([CONFIG_PATH + "peer_disable.sh", "-p", l_peer['peer']])
            process.wait()

if __name__ == "__main__":
    sys.exit(main())
