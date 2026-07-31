import math

costPerPayment = float(input('Input the cost per payment: '))
interval = int(input('Input the interval: '))
period = int(input('Input the number of payments (period): '))
interest = float(input('Input the interest rate per year (%)')) / 100

total_sum = 0
year = interval

for i in range(period):
    total_sum = total_sum + costPerPayment / (1 + interest) ** year
    year += interval

print("Total sum is", total_sum)
