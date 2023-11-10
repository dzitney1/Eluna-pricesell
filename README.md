# Eluna-pricesell
 A lua script pricing and selling items based on AH data from nexushub with Eluna.

 This is a script for selling and pricing items using marketdata from NexusHub.
In it's default configuration it will check the market value of the linked item on eu/us servers for the last 16 months
The global mean is calculated then any results more than two standard deviations from that mean are dropped and the average is taken
Payout cap is in place as a means to attempt 10kgold + payouts on random items
the market value is divided by 5 for arbitrary reasons.  It's just what felt right to us!

Installation
    Move the script into your lua_scripts folder.
    Download and move json.lua from https://github.com/rxi/json.lua to your lua_scripts folder.