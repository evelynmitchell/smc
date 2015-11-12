#!/usr/bin/python

import os, sys, time

if not 'SMC' in os.environ:
    os.environ['SMC'] = os.path.join(os.environ['HOME'], '.smc')
SMC = os.environ['SMC']
if not os.path.exists(SMC):
    os.makedirs(SMC)

# ensure that PATH starts with ~/bin, so user can customize what gets run
os.environ['PATH']="%s:%s"%(os.path.join(os.environ['HOME'], 'bin'), os.environ['PATH'])

def cmd(s):
    print s
    if os.system(s):
       sys.exit(1)

def create_root_link():
    root_link = os.path.join(SMC, "root")
    if not os.path.exists(root_link):
        try:
            cmd("cd '%s'; ln -s / root"%SMC)
        except:
            print "WARNING: problem making root link"

def started():
    return os.path.exists("%s/local_hub/local_hub.port"%SMC)

def main():
    create_root_link()

    # Start local hub server
    cmd("smc-local-hub start")

    i=0
    while not started():
        time.sleep(0.1)
        i += 1
        print i,
        sys.stdout.flush()
        if i >= 100:
            sys.exit(1)

if __name__ == "__main__":
    main()
