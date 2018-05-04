#Eternal Lands Bot Comparer
#Compares buying/selling from bots in eternal lands  so you can make a little profit!

package require sqlite3
package require http
package require tdom

sqlite3 DB el_bots.sqlite -create true

proc createTables {} {
	DB eval { CREATE TABLE bots (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT COLLATE NOCASE, location TEXT COLLATE NOCASE);
	CREATE TABLE items (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT COLLATE NOCASE);
	
	CREATE TABLE buying (id INTEGER PRIMARY KEY AUTOINCREMENT, 
	item_id INTEGER, bot_id INTEGER, quantity INTEGER, price INTEGER);
	
	CREATE TABLE selling (id INTEGER PRIMARY KEY AUTOINCREMENT, 
	item_id INTEGER, bot_id INTEGER, quantity INTEGER, price DOUBLE);}
}

array set settings {
	bots_url http://bots.el-services.net/ 
	waitTime 1000
	useragent "Mozilla/5.0 (Windows NT 6.3; rv:36.0) Gecko/20100101 Firefox/36.0"
}

http::config -useragent $settings(useragent)
#1. Get page http://bots.el-services.net/ 
#2. Select links form #botnames
proc startIndexingBots {} {
	global settings
	set data [http::data [http::geturl $settings(bots_url)]]
	set doc [dom parse -html $data]
	set root [$doc documentElement]
	set botnames [$root getElementById botnames]
	set all_bots [$botnames selectNodes {//a[@class="arrow"]}]
	puts "Getting all bots $all_bots"
	getUrlOfBots $all_bots
	#Update details
	DB eval {UPDATE buying SET price=REPLACE(price,',',''); UPDATE selling SET price=REPLACE(price,',','');}
}

proc getUrlOfBots {bots} {
	global settings 
	set i 0
	set total [llength $bots]
	puts "Going through all the bots ($total)"
	foreach bot $bots {
	#	if {$i>2} { break }
		set url [$bot getAttribute href]
		processBot $url
		after 1000
		incr i
	}
}

#3 Go through each BOT (1000 ms wait time)
# A. Get All "Selling items name, quantity & price"
# B. Get all Buying items (name, quantity & price)
# C. Data must be saved in a DB (sqlite)
proc processBot { url } {
	global settings
	set data [http::data [http::geturl $settings(bots_url)/$url	]]
		
	set doc [dom parse -html $data]
	set root [$doc documentElement]
	
	set botname [[$root selectNodes {//td[@class="botinfo-botname"]} ] asText]
	set location [[$root find class botinfo-location ] asText]
	set botid [DB eval {INSERT INTO bots (name,location) VALUES ($botname,$location) ; SELECT last_insert_rowid() FROM bots LIMIT 1}]
	#Go through selling
	#div#selling
	set selling [$root selectNodes {//div[@id="selling"]//tr[@bgcolor="#E9ECCF"]}]
	foreach sell $selling {
		getItemInfo $botid $sell sell
	}
	
	#GO Through buying
	set buying [$root selectNodes {//div[@id="purchasing"]//tr[@bgcolor="#E9ECCF"]}]

	foreach buy $buying {
		getItemInfo $botid $buy buy
	}
	puts "Successfully got url for $botname : $url"
}

proc getItemInfo {botid node what} {
	upvar root root
	#set name	[$node [[$node find {//td[@class="public2"]}] asText]]
	#set pr	[$node [$node selectNodes {//td[@class="public_right"]}] ]
#	foreach {dom}  $pr var {quantity price} {
	#	set $var [$dom asText]
#	}

	set name [[$node child  3] asText]
	set quantity [[$node child  4] asText]
	set price [[$node child  5] asText]
	
	set itemid [DB eval {SELECT id FROM items where name=$name}]
	if {$itemid == "" } {
		
		set itemid [DB eval {INSERT INTO items (name) VALUES ($name) ;  SELECT last_insert_rowid() FROM items LIMIT 1}]
	}
	if {$what == "buy" } {
		DB eval {INSERT INTO buying (item_id,bot_id,quantity,price) VALUES 
			($itemid,$botid,$quantity,$price)}
	} elseif {$what == "sell"} {
		DB eval {INSERT INTO selling (item_id,bot_id,quantity,price) VALUES 
			($itemid,$botid,$quantity,$price)}
	}
	
}

#4. Compare all data in SQL (easier) and generate:
#A. HTML file with best buying/selling price 
#B. HTML file with items you can make a profit from

proc generateHTMLStatistics {} {
	
set items [DB eval  {
SELECT  (SELECT name from items where id=s.item_id) as Item , 
(SELECT name FROM bots where id=s.bot_id) as Seller, (SELECT name FROM bots where id=b.bot_id) as Buyer ,
s.price as "Seller Price", b.price as "Buyer Price",
s.quantity as "Seller quantity", b.quantity as "Buyer Quantity", b.price-s.price as profit
FROM selling s, buying b
WHERE
s.item_id=b.item_id
AND s.price < b.price
ORDER BY  b.price-s.price DESC
}]

set file [open el_bots_comparison.html w]
puts $file "<h1>Profit generator by LordPraslea ([clock format [clock seconds]])</h1>"
	puts $file "<tr><td>item</td> <td>seller</td> <td>buyer</td> <td>seller_price</td> <td>buyer_price</td> <td>seller_quantity</td> 
	<td>buyer_quantity</td> <td>profit</td>
	 </tr>"
puts $file <table>
foreach {item seller buyer seller_price buyer_price seller_quantity buyer_quantity profit} $items {
	puts $file "<tr><td>$item</td> <td>$seller</td> <td>$buyer</td> <td>$seller_price</td>  <td>$buyer_price</td>  <td>$seller_quantity</td> 
	<td>$buyer_quantity</td> <td>$profit</td>
	 </tr>"
}

close $file

}

createTables
startIndexingBots
generateHTMLStatistics
