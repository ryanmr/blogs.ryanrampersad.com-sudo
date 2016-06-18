

echo "removing /public"
rm -rf public

echo "generating"
hugo

echo "sync'ing"
# use -anv to test syncing
rsync -av ./public/ ryan@ryanrampersad.com:www/blogs.ryanrampersad.com/public_html/sudo/
