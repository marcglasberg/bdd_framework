Feature: Average Price


  Scenario Outline: Buying and Selling stocks changes the average price.
    Given The user has <Quantity> shares of <Ticker> at <At> dollars each.
    When The user <BuyOrSell> <How many> of these stock at <Price> for each share.
    Then The number of shares becomes <Quantity> plus/minus <How many>.
    And The average price for the stock becomes <Average Price>.
    Examples: 
      | Ticker | Quantity | At    | BuyOrSell | How many | Price | Average Price |
      | IBM    | 10       | 100.0 | buy       | 2        | 50.0  | 91.67         |
      | IBM    | 8        | 200.0 | sell      | 3        | 30.0  | 302.0         |

  Scenario Outline: Buying and Selling stocks changes the average price.
    Given The user has <Quantity> shares of <Ticker> at <At> dollars each.
    When The user <BuyOrSell> <How many> of these stock at <Price> for each share.
    Then The number of shares becomes <Quantity> plus/minus <How many>.
    And The average price for the stock becomes <Average Price>.
    Examples: 
      | Ticker | Quantity | At    | BuyOrSell | How many | Price | Average Price |
      | IBM    | 10       | 100.0 | buy       | 2        | 50.0  | 91.67         |
      | IBM    | 8        | 200.0 | sell      | 3        | 30.0  | 302.0         |
