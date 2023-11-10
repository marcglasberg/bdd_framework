Feature: Buying and Selling Stocks


  Scenario: Buying stocks.
    Given The user has 120 dollars in cash-balance.
    And IBM price is 30 dollars.
    And The user has no IBM stocks.
    When The user buys 1 IBM.
    Then The user now has 1 IBM.
    And The cash-balance is now 90 dollars.

  Scenario: Buying stocks.
    Given The user has 120 dollars in cash-balance.
    And IBM price is 30 dollars.
    And The user has no IBM stocks.
    When The user buys 1 IBM.
    Then The user now has 1 IBM.
    And The cash-balance is now 90 dollars.

  Scenario: Selling stocks.
    Given The user has 120 dollars in cash-balance.
    And The current stock prices are as such:
      | Ticker | Price |
      | AAPL   | 50.25 |
      | IBM    | 30.0  |
      | GOOG   | 60.75 |
    And The user Portfolio contains:
      | Ticker | Quantity |
      | AAPL   | 5        |
      | IBM    | 3        |
      | GOOG   | 12       |
    When The user sells 1 IBM.
    Then The user now has 2 IBM.
    And AAPL is still 5, and GOOG is still 12.
    And The cash-balance is now 150 dollars.

  Scenario: Selling stocks.
    Given The user has 120 dollars in cash-balance.
    And The current stock prices are as such:
      | Ticker | Price |
      | AAPL   | 50.25 |
      | IBM    | 30.0  |
      | GOOG   | 60.75 |
    And The user Portfolio contains:
      | Ticker | Quantity |
      | AAPL   | 5        |
      | IBM    | 3        |
      | GOOG   | 12       |
    When The user sells 1 IBM.
    Then The user now has 2 IBM.
    And AAPL is still 5, and GOOG is still 12.
    And The cash-balance is now 150 dollars.

  Scenario: Selling stocks you don’t have.
    Given The user has 120 dollars in cash-balance.
    And IBM price is 30 dollars.
    And The user has no IBM stocks.
    When The user sells 1 IBM.
    Then We get an error.
    And The user continues to have 0 IBM.
    And The cash-balance continues to be 120 dollars.

  Scenario: Selling stocks you don’t have.
    Given The user has 120 dollars in cash-balance.
    And IBM price is 30 dollars.
    And The user has no IBM stocks.
    When The user sells 1 IBM.
    Then We get an error.
    And The user continues to have 0 IBM.
    And The cash-balance continues to be 120 dollars.
