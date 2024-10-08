-- Расчет суммарного кол-ва посетителей
select count(distinct visitor_id)
from sessions;

-- Расчет кол-ва посетителей по источникам
with tab as (
    select
        count(visitor_id) as visitor_count,
        upper(substring(
            case
                when source ilike '%ya%' then 'yandex'
                when source ilike '%tg%' or source ilike '%teleg%'
                    then 'telegram'
                when source ilike '%vk%' then 'vkontakte'
                when source ilike '%facebook%' then 'facebook'
                when source ilike '%tw%' then 'twitter'
                else source
            end, 1, 1
        )) || substring(
            case
                when source ilike '%ya%' then 'yandex'
                when source ilike '%tg%' or source ilike '%teleg%'
                    then 'telegram'
                when source ilike '%vk%' then 'vkontakte'
                when source ilike '%facebook%' then 'facebook'
                when source ilike '%tw%' then 'twitter'
                else source
            end, 2
        ) as source
    from sessions
    group by 2
)

select
    case
        when visitor_count < 1000 then 'other'
        else source
    end as source,
    sum(visitor_count) as visitor_count
from tab
group by 1
order by 2 desc;

-- Расчет кол-ва посетителей по дням месяца
select
    to_char(visit_date, 'DD-MM-YYYY') as visit_date,
    count(distinct visitor_id) as visitor_count
from sessions
group by 1
order by 1;

-- Расчет кол-ва посетителей по неделям
select
    to_char(visit_date, 'W') as week_of_month,
    count(distinct visitor_id) as visitor_count
from sessions
group by 1
order by 1;

-- Расчет кол-ва посетителей по дням недели
with weekly_visits as (
    select
        extract(dow from s.visit_date) as day_of_week,
        count(distinct s.visitor_id) as visitor_count
    from sessions as s
    group by 1
)

select
    wv.day_of_week,
    wv.visitor_count,
    case
        when wv.day_of_week = 0 then '7.Sunday'
        when wv.day_of_week = 1 then '1.Monday'
        when wv.day_of_week = 2 then '2.Tuesday'
        when wv.day_of_week = 3 then '3.Wednesday'
        when wv.day_of_week = 4 then '4.Thursday'
        when wv.day_of_week = 5 then '5.Friday'
        when wv.day_of_week = 6 then '6.Saturday'
    end as day_name
from weekly_visits as wv
order by 1;

-- Расчет суммарного кол-ва лидов
select count(distinct lead_id) as leads_count
from leads;

-- Расчет кол-ва созданных лидов по дням месяца
select
    l.created_at::date as creation_date,
    count(distinct l.lead_id) as leads_count
from leads as l
group by 1
order by 1 asc;

-- Расчет метрик (cpu, cpl, cppu, roi) для utm_source
with sales as (
    select
        s.visitor_id,
        s.visit_date::date as visit_date,
        s.source,
        s.medium,
        s.campaign,
        l.lead_id,
        l.amount,
        l.created_at,
        l.closing_reason,
        l.status_id,
        row_number() over (
            partition by s.visitor_id
            order by s.visit_date desc
        ) as sale_count
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date::date <= l.created_at::date
    where s.medium != 'organic'
),

costs as (
    select
        vk.campaign_date::date as campaign_date,
        vk.utm_source,
        vk.utm_medium,
        vk.utm_campaign,
        sum(vk.daily_spent) as daily_spent
    from vk_ads as vk
    group by 1, 2, 3, 4
    union all
    select
        ya.campaign_date::date as campaign_date,
        ya.utm_source,
        ya.utm_medium,
        ya.utm_campaign,
        sum(ya.daily_spent) as daily_spent
    from ya_ads as ya
    group by 1, 2, 3, 4
),

tab as (
    select
        s.visit_date::date as visit_date,
        s.source as utm_source,
        s.medium as utm_medium,
        s.campaign as utm_campaign,
        c.daily_spent as total_cost,
        count(s.visitor_id) as visitors_count,
        count(s.lead_id) as leads_count,
        count(s.lead_id) filter (
            where s.closing_reason = 'Успешно реализовано' or s.status_id = 142
        ) as purchases_count,
        sum(s.amount) as revenue
    from sales as s
    left join costs as c
        on
            s.source = c.utm_source
            and s.medium = c.utm_medium
            and s.campaign = c.utm_campaign
            and s.visit_date::date = c.campaign_date
    where s.sale_count = 1
    group by 1, 2, 3, 4, 5
)

select
    tab.utm_source,
    coalesce(
        case
            when sum(tab.visitors_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.visitors_count), 2)
        end,
        0
    ) as cpu,
    coalesce(
        case
            when sum(tab.leads_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.leads_count), 2)
        end,
        0
    ) as cpl,
    coalesce(
        case
            when sum(tab.purchases_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.purchases_count), 2)
        end,
        0
    ) as cppu,
    coalesce(
        case
            when sum(tab.total_cost) = 0 then 0
            else
                round(
                    (sum(tab.revenue) - sum(tab.total_cost))
                    / sum(tab.total_cost) * 100, 2
                )
        end,
        0
    ) as roi
from tab
where tab.utm_source in ('vk', 'yandex')
group by 1;


-- Расчет метрик (cpu, cpl, cppu, roi) для utm_source, utm_medium и utm_campaign
with sales as (
    select
        s.visitor_id,
        s.visit_date::date as visit_date,
        s.source,
        s.medium,
        s.campaign,
        l.lead_id,
        l.amount,
        l.created_at,
        l.closing_reason,
        l.status_id,
        row_number() over (
            partition by s.visitor_id
            order by s.visit_date desc
        ) as sale_count
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date::date <= l.created_at::date
    where s.medium != 'organic'
),

costs as (
    select
        vk.campaign_date::date as campaign_date,
        vk.utm_source,
        vk.utm_medium,
        vk.utm_campaign,
        sum(vk.daily_spent) as daily_spent
    from vk_ads as vk
    group by 1, 2, 3, 4
    union all
    select
        ya.campaign_date::date as campaign_date,
        ya.utm_source,
        ya.utm_medium,
        ya.utm_campaign,
        sum(ya.daily_spent) as daily_spent
    from ya_ads as ya
    group by 1, 2, 3, 4
),

tab as (
    select
        s.visit_date::date as visit_date,
        s.source as utm_source,
        s.medium as utm_medium,
        s.campaign as utm_campaign,
        c.daily_spent as total_cost,
        count(s.visitor_id) as visitors_count,
        count(s.lead_id) as leads_count,
        count(s.lead_id) filter (
            where s.closing_reason = 'успешно реализовано' or s.status_id = 142
        ) as purchases_count,
        sum(s.amount) as revenue
    from sales as s
    left join costs as c
        on
            s.source = c.utm_source
            and s.medium = c.utm_medium
            and s.campaign = c.utm_campaign
            and s.visit_date::date = c.campaign_date
    where s.sale_count = 1
    group by 1, 2, 3, 4, 5
)

select
    tab.utm_source,
    tab.utm_medium,
    tab.utm_campaign,
    coalesce(
        case
            when sum(tab.visitors_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.visitors_count), 2)
        end,
        0
    ) as cpu,
    coalesce(
        case
            when sum(tab.leads_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.leads_count), 2)
        end,
        0
    ) as cpl,
    coalesce(
        case
            when sum(tab.purchases_count) = 0 then 0
            else round(sum(tab.total_cost) / sum(tab.purchases_count), 2)
        end,
        0
    ) as cppu,
    coalesce(
        case
            when sum(tab.total_cost) = 0 then 0
            else
                round(
                    (sum(tab.revenue) - sum(tab.total_cost))
                    / sum(tab.total_cost) * 100, 2
                )
        end,
        0
    ) as roi
from tab
where tab.utm_source in ('vk', 'yandex')
group by 1, 2, 3;

-- Расчет конверсий
with sales as (
    select
        s.visitor_id,
        s.visit_date::date,
        s.source,
        s.medium,
        s.campaign,
        l.lead_id,
        l.amount,
        l.created_at,
        l.closing_reason,
        l.status_id,
        row_number() over (
            partition by s.visitor_id
            order by s.visit_date desc
        ) as sale_count
    from sessions as s
    left join leads as l
        on
            s.visitor_id = l.visitor_id
            and s.visit_date::date <= l.created_at::date
    where s.medium != 'organic'
),

costs as (
    select
        vk.campaign_date::date,
        vk.utm_source,
        vk.utm_medium,
        vk.utm_campaign,
        sum(vk.daily_spent) as daily_spent
    from vk_ads as vk
    group by
        1, 2, 3, 4
    union all
    select
        ya.campaign_date::date,
        ya.utm_source,
        ya.utm_medium,
        ya.utm_campaign,
        sum(ya.daily_spent) as daily_spent
    from ya_ads as ya
    group by
        1, 2, 3, 4
),

tab as (
    select
        s.visit_date,
        s.source as utm_source,
        s.medium as utm_medium,
        s.campaign as utm_campaign,
        c.daily_spent as total_cost,
        count(s.visitor_id) as visitors_count,
        count(s.lead_id) as leads_count,
        count(s.lead_id) filter (
            where s.closing_reason = 'Успешно реализовано'
            or s.status_id = 142
        ) as purchases_count,
        sum(s.amount) as revenue
    from sales as s
    left join costs as c
        on
            s.source = c.utm_source
            and s.medium = c.utm_medium
            and s.campaign = c.utm_campaign
            and s.visit_date::date = c.campaign_date
    where s.sale_count = 1
    group by 1, 2, 3, 4, 5
)

select
    round(
        sum(leads_count) / sum(visitors_count) * 100, 2
    ) as clicks_to_leads_conversion,
    round(
        sum(purchases_count) / sum(leads_count) * 100, 2
    ) as leads_to_purchases_conversion
from tab;

-- Расчет трат по каналам
with tab as (
    select
        vk.campaign_date::date,
        vk.utm_source,
        vk.utm_medium,
        vk.utm_campaign,
        sum(vk.daily_spent) as daily_spent
    from vk_ads as vk
    group by
        1, 2, 3, 4
    union all
    select
        ya.campaign_date::date,
        ya.utm_source,
        ya.utm_medium,
        ya.utm_campaign,
        sum(ya.daily_spent) as daily_spent
    from ya_ads as ya
    group by
        1, 2, 3, 4
)

select
    tab.campaign_date::date,
    tab.utm_source,
    tab.utm_medium,
    tab.utm_campaign,
    tab.daily_spent
from tab
order by 1;

--Расчет кол-ва дней, за которое закрывается 90% лидов 
--с момента перехода по рекламе
with tab as (
    select
        s.visitor_id,
        s.visit_date::date,
        l.lead_id,
        l.created_at::date,
        l.created_at::date - s.visit_date::date as days_passed,
        ntile(10) over (
            order by l.created_at::date - s.visit_date::date
        ) as ntile
    from sessions as s
    inner join leads as l
        on s.visitor_id = l.visitor_id
    where
        l.closing_reason = 'Успешная продажа'
        and s.visit_date::date <= l.created_at::date
)

select max(days_passed) as days_passed
from tab
where ntile = 9;

--Расчет кол-ва визитов и кол-ва рекламных кампаний по дням месяца
select
    s.visit_date::date as visit_date,
    count(distinct s.visitor_id) as visitor_count,
    count(distinct s.campaign) as campaign_count
from sessions as s
where s.source ilike '%vk%' or s.source ilike '%ya%'
group by 1
order by 1;

--Кол-во уникальных посетителей, лидов и закрытых лидов для воронки продаж
with tab as (
    select
        'visitors' as category,
        count(distinct visitor_id) as counta
    from sessions

    union all

    select
        'leads' as category,
        count(distinct lead_id) as counta
    from leads

    union all

    select
        'purchased_leads' as category,
        count(lead_id) filter (
            where closing_reason = 'Успешно реализовано' or status_id = 142
        ) as counta
    from leads
)

select
    t.category,
    t.counta
from tab as t
order by 2 desc;
