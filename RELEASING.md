# Releasing

Cut a release (tag + maintenance branch, then push):

```
git tag -a v0.1.0 -m "Release 0.1.0"
git switch -c release-0.1
git push origin v0.1.0 release-0.1
```

Ship a fix on that line (commit onto the branch, then tag):

```
git switch release-0.1
# ...commit fix...
git tag -a v0.1.1 -m "Release 0.1.1"
git push origin release-0.1 v0.1.1
```
