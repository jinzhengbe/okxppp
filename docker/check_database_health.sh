#!/bin/bash

# 检查InfluxDB健康状态
check_influxdb() {
  echo "检查InfluxDB健康状态..."
  if curl -s http://localhost:8086/ping > /dev/null; then
    echo "InfluxDB运行正常"
    return 0
  else
    echo "InfluxDB未运行或无法访问"
    return 1
  fi
}

# 检查PostgreSQL健康状态
check_postgres() {
  echo "检查PostgreSQL健康状态..."
  if pg_isready -h localhost -p 5432 > /dev/null 2>&1; then
    echo "PostgreSQL运行正常"
    return 0
  else
    echo "PostgreSQL未运行或无法访问"
    return 1
  fi
}

# 主函数
main() {
  influx_status=0
  postgres_status=0
  
  check_influxdb || influx_status=1
  check_postgres || postgres_status=1
  
  if [ $influx_status -eq 0 ] && [ $postgres_status -eq 0 ]; then
    echo "所有数据库服务运行正常"
    exit 0
  else
    echo "一个或多个数据库服务未运行"
    exit 1
  fi
}

# 执行主函数
main 