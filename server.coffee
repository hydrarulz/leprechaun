KrakenClient = require 'kraken-api'

# Config
kraken_config = require './kraken-config'
kraken_api_key = kraken_config.api_key
kraken_api_secret = kraken_config.api_secret
kraken_timeout = 60000 * 2 # 2 minutes

kraken = new KrakenClient \
	kraken_api_key
	, kraken_api_secret

least_difference = 2

buy_price = 0
sell_price = 0
fee_percent = 0.4

# Set up moving average
MA = require './js/moving_average/moving_average'

# Set up mandrill for mails
mandrill = require 'mandrill-api/mandrill'
mandrill_config = require './mandrill-config'
mandrill_client = new mandrill.Mandrill mandrill_config.api_key
message =
	'from_email': mandrill_config.send_from
	'to': mandrill_config.send_to
	'important': true
# If we already bought the bitcoin
invested = false

# If we warned about the movement
price_warn = false

# Get balance
kraken.api \
	'Balance'
	, null
	, (error, data)->

		console.log "Balance"

		if error
			console.log error
		else
			console.log data

get_market_price = (callback)->

	console.log "Getting market prices"

	kraken.api \
		'Ticker'
		, {
			'pair': 'XXBTZEUR'
		}
		, (error, data) ->
			prices = {}

			if error
				console.log error
			else
				prices =
					'market_buy': data.result['XXBTZEUR']['a'][0]
					'market_sell': data.result['XXBTZEUR']['b'][0]

			if callback
				callback(error, prices)

# Sell
sell = (difference, volume_long, volume_short)->
	get_market_price \
		(error, prices)->
			# Check if I the selling price is higher (with fee)
			if prices.market_sell <= (buy_price + (buy_price * fee_percent / 100)) and price_warn is false
				message['subject'] = "Trying to sell but the selling price is too low"
				message['text'] = ''
				message['html'] = "Selling price #{prices.market_sell}<br />"
				message['html'] += "Bought at #{buy_price}, with fee must be at least #{buy_price * fee_percent / 100}<br />"
				mandrill_client.messages.send \
					'message' : message
					, (result)->
						console.log result
				price_warn = true
				return false

			price_warn = false

			# If we can sell, we do it
			timestamp = new Date()
			console.log "#{timestamp.toUTCString()} TRANSACTION Selling at #{prices.market_sell}"
			invested = false
			sell_price = prices.market_sell

			message['subject'] = "You should sell at #{prices.market_sell}"
			message['text'] = ''
			message['html'] = ''
			message['html'] += "Current difference is #{difference} <br />"
			message['html'] += "Volume for long is #{volume_long}<br />"
			message['html'] += "Volume for short is #{volume_short}<br />"
			mandrill_client.messages.send \
				'message' : message
				, (result)->
					console.log result


# Buy
buy = (difference, volume_long, volume_short)->
	get_market_price \
		(error, prices)->
			timestamp = new Date()
			console.log "#{timestamp.toUTCString()} TRANSACTION Buying at #{prices.market_buy}"
			invested = true
			buy_price = prices.market_buy

			message['subject'] = "You should buy at #{prices.market_sell}"
			message['text'] = ''
			message['html'] = ''
			message['html'] += "Current difference is #{difference} <br />"
			message['html'] += "Volume for long is #{volume_long}<br />"
			message['html'] += "Volume for short is #{volume_short}<br />"
			mandrill_client.messages.send \
				'message' : message
				, (result)->
					console.log result


check_moving_average = ()->
	console.log "-----------------------------------"
	kraken.api \
		'Trades'
		,{
			'pair' : 'XXBTZEUR'
		}
		, (error, data)->
			if error
				console.log error
			else
				#BTZEUR
				data_set = data.result['XXBTZEUR']
				console.log "Data set length #{data_set.length}"

				# Moving average
				ma_long_size = parseInt data_set.length / 2, 10
				ma_short_size = parseInt data_set.length / 5, 10

				# Volumes
				volume_long = 0
				volume_short = 0

				# Moving average long
				ma_long = new MA(ma_long_size)
				for i in [data_set.length - ma_long_size..data_set.length - 1]

					trade_data =
						'price'         : parseFloat data_set[i][0]
						'volume'        : parseFloat data_set[i][1]
						'time'          : parseFloat data_set[i][2]
						'buy/sell'      : data_set[i][3]
						'market/limit'  : data_set[i][4]
						'miscellaneous' : data_set[i][5]

					volume_long += trade_data['volume']

					ma_long.push \
						i
						, trade_data['price']

				ma_long_value = ma_long.movingAverage()
				console.log "Moving average for last #{ma_long_size} = #{ma_long_value}"

				# Moving average short
				ma_short = new MA(ma_short_size)
				for i in [data_set.length - ma_short_size..data_set.length - 1]

					trade_data =
						'price'         : parseFloat data_set[i][0]
						'volume'        : parseFloat data_set[i][1]
						'time'          : parseFloat data_set[i][2]
						'buy/sell'      : data_set[i][3]
						'market/limit'  : data_set[i][4]
						'miscellaneous' : data_set[i][5]

					volume_short += trade_data['volume']

					ma_short.push \
						i
						, trade_data['price']

				ma_short_value = ma_short.movingAverage()
				console.log "Moving average for last #{ma_short_size} = #{ma_short_value}"

				# Check if we should and can sell
				if (ma_short_value + least_difference < ma_long_value) and invested
					console.log "Going down let's sell"

					difference = Math.abs(ma_short_value - ma_long_value)

					# Sell all
					sell(difference, volume_long, volume_short)

					invested = true
				# Check if we should and can buy
				else if (ma_short_value - least_difference > ma_long_value) and not invested
					console.log "Going up let's buy"

					difference = Math.abs(ma_short_value - ma_long_value)

					# Buy as much as you can
					buy(difference, volume_long, volume_short)

					invested = false
				else
					console.log "Difference is #{Math.abs(ma_short_value - ma_long_value)}"
					console.log "Invested = #{invested}"

				# Sleep for a while
				setTimeout check_moving_average, kraken_timeout


check_moving_average()

