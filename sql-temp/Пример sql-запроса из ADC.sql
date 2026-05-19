BEGIN
    TRUNCATE TABLE sales_ranked;

    INSERT INTO sales_ranked (
        sale_id, product_id, sale_date, amount,
        rank_in_product, prev_amount, running_total
    )
    SELECT
        s.id,
        s.product_id,
        s.sale_date,
        s.amount,
        ROW_NUMBER() OVER (PARTITION BY s.product_id ORDER BY s.sale_date) AS rank_in_product,
        LAG(s.amount) OVER (PARTITION BY s.product_id ORDER BY s.sale_date) AS prev_amount,
        SUM(s.amount) OVER (PARTITION BY s.product_id ORDER BY s.sale_date
                            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
    FROM sales s;
END;