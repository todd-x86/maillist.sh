# Maillist.sh
*Mail list manager written in Bash*

# Introduction
Maillist.sh is a mail list manager written in Bash to be a "relatively easy-to-setup" mailing list manager and possibly a learning tool.  At the moment, Maillist.sh supports a small subscriber list (30 or fewer e-mails) and is entirely backed by Bash and a Linux file system.  Maillist.sh does not function as a daemon but is subprocessed by an MTA (mail transfer agent) which passes e-mails through stdin directly to the Maillist.sh subprocess.

# Why???

I was toiling one weekend trying to setup GNU Mailman on my web server when I realized one of the configurations involved Exim (mail transfer agent)piping the contents of the e-mail to a Mailman wrapper executable.  After getting Mailman partially setup, I felt that a simple mail list manager could conceivably be written in Bash and serve a similar purpose.  I also just wanted to challenge myself to do something crazy like this.

# Purpose / Motivation

Maillist.sh's goal is to be a portable and easily installed for small-scale uses.  My own use-case involves sending communication e-mails to a small list of volunteers under an organization.  Bash's own limitations (and the sanity lost when developing and debugging overly-complicated Bash scripts) dictate how far Maillist.sh can scale.

# Why didn't you use a programming language like Go or Rust?

Honestly, my selfish motivation was to see if something like this could be done in pure Bash using mostly built-in Linux utilities.

# Does it web scale?

No.
