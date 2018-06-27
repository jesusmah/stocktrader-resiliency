su - db2inst1 -c 'db2 connect to STOCKTRD; db2 "select * from stock" > /tmp/stock.txt; db2 "select * from portfolio" > /tmp/portfolio.txt'
