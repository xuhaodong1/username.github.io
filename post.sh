hexo generate
cp -r public/ docs/
git add .
git commit -m "$1"
git pull origin master
git push origin master
