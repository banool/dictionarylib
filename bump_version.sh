perl -i -pe 's/^(version:\s+\d+\.\d+\.)(\d+)$/$1.($2+1).$3/e' pubspec.yaml
