su - db2inst1 -c 'db2 connect to STOCKTRD; db2 -x "select OWNER from portfolio" > /tmp/users.txt'
