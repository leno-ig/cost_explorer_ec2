# cost_explorer_ec2

## sample
```
docker-compose run ruby ruby -I ./lib -r cost_explorer_ec2 -e "CostExplorerEc2.new('ap-northeast-1', 'akid', 'secret').to_csv('./sample.csv')"
```
