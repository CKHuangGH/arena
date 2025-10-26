docker build -t chuangtw/iot:latest -f Dockerfile .

docker login -u chuangtw

docker push chuangtw/iot:latest