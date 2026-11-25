begin;

create table wn_private.quiz_schedule (
  day date primary key,
  id text not null unique,
  prompt text not null,
  answer text not null references public.wn_countries(id),
  options text[] not null check (cardinality(options) = 4 and answer = any(options))
);
create unique index quiz_prompt_once on wn_private.quiz_schedule (lower(trim(prompt)));
create table wn_private.quiz_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  day date not null references wn_private.quiz_schedule(day),
  choice text not null references public.wn_countries(id),
  primary key (user_id, day)
);
alter table wn_private.quiz_schedule enable row level security;
alter table wn_private.quiz_attempts enable row level security;
revoke all on wn_private.quiz_schedule, wn_private.quiz_attempts from public, anon, authenticated;

create function wn_private.check_quiz_options() returns trigger language plpgsql set search_path='' as $$
begin
  if (select count(*) from public.wn_countries where id=any(new.options))<>4 then
    raise exception 'A quiz needs four distinct catalog countries';
  end if;
  return new;
end $$;
revoke all on function wn_private.check_quiz_options() from public,anon,authenticated;
create trigger check_quiz_options before insert on wn_private.quiz_schedule
for each row execute function wn_private.check_quiz_options();

-- Keep published slots immutable when extending the calendar.
create function wn_private.keep_quiz_slot() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'Published quiz slots are immutable'; end $$;
create trigger keep_quiz_slot before update or delete on wn_private.quiz_schedule
for each row execute function wn_private.keep_quiz_slot();

insert into wn_private.quiz_schedule(day,id,prompt,answer,options) values
('2026-11-24','capital-to','Which country has Nuku''alofa as its capital?','TO',array['WS','TV','TO','BW']),
('2026-11-25','capital-at','Which country has Vienna as its capital?','AT',array['SI','BN','HU','AT']),
('2026-11-26','capital-gq','Which country named Ciudad de la Paz its capital in 2026?','GQ',array['ST','GQ','AO','CM']),
('2026-11-27','capital-kh','Which country has Phnom Penh as its capital?','KH',array['CI','KH','TH','TL']),
('2026-11-28','capital-ng','Which country has Abuja as its capital?','NG',array['HT','MR','GN','NG']),
('2026-11-29','capital-jm','Which country has Kingston as its capital?','JM',array['BS','VC','PY','JM']),
('2026-11-30','capital-pw','Which country has Ngerulmud as its capital?','PW',array['PW','MH','FM','PL']),
('2026-12-01','capital-tg','Which country has Lomé as its capital?','TG',array['BT','TG','GN','MR']),
('2026-12-02','capital-sy','Which country has Damascus as its capital?','SY',array['JO','MU','SY','AE']),
('2026-12-03','capital-ge','Which country has Tbilisi as its capital?','GE',array['GE','BH','SA','PS']),
('2026-12-04','capital-bd','Which country has Dhaka as its capital?','BD',array['PW','IN','BD','IR']),
('2026-12-05','capital-de','Which country has Berlin as its capital?','DE',array['DE','MC','NL','CH']),
('2026-12-06','capital-am','Which country has Yerevan as its capital?','AM',array['SY','PS','CZ','AM']),
('2026-12-07','capital-gw','Which country has Bissau as its capital?','GW',array['GW','SN','NG','TG']),
('2026-12-08','capital-hu','Which country has Budapest as its capital?','HU',array['AT','HU','PL','PE']),
('2026-12-09','capital-tt','Which country has Port of Spain as its capital?','TT',array['JM','TT','KN','AT']),
('2026-12-10','capital-hr','Which country has Zagreb as its capital?','HR',array['BA','HR','RS','LI']),
('2026-12-11','capital-dk','Which country has Copenhagen as its capital?','DK',array['SE','DK','FI','CV']),
('2026-12-12','capital-mn','Which country has Ulan Bator as its capital?','MN',array['KP','CN','LK','MN']),
('2026-12-13','capital-bt','Which country has Thimphu as its capital?','BT',array['JM','BD','BT','PK']),
('2026-12-14','capital-th','Which country has Bangkok as its capital?','TH',array['TH','SG','ID','VE']),
('2026-12-15','capital-va','Which city-state inside Rome serves as its own capital?','VA',array['CY','VA','MT','AD']),
('2026-12-16','capital-mh','Which country has Majuro as its capital?','MH',array['MG','FM','MH','NR']),
('2026-12-17','capital-fr','Which country has Paris as its capital?','FR',array['IL','FR','LU','BE']),
('2026-12-18','capital-kg','Which country has Bishkek as its capital?','KG',array['UZ','TJ','AL','KG']),
('2026-12-19','capital-kz','Which country has Astana as its capital?','KZ',array['CF','KZ','KG','TM']),
('2026-12-20','capital-gt','Which country has Guatemala City as its capital?','GT',array['SV','RO','GT','NI']),
('2026-12-21','capital-si','Which country has Ljubljana as its capital?','SI',array['PK','PL','SK','SI']),
('2026-12-22','capital-st','Which country has São Tomé as its capital?','ST',array['GA','UY','CG','ST']),
('2026-12-23','capital-uy','Which country has Montevideo as its capital?','UY',array['PY','SE','UY','CO']),
('2026-12-24','capital-us','Which country has Washington D.C. as its capital?','US',array['TO','CA','US','MX']),
('2026-12-25','capital-ug','Which country has Kampala as its capital?','UG',array['MH','UG','MU','MG']),
('2026-12-26','capital-lb','Which country has Beirut as its capital?','LB',array['LB','BH','LC','TR']),
('2026-12-27','capital-be','Which country has Brussels as its capital?','BE',array['BE','GD','FR','NL']),
('2026-12-28','capital-jo','Which country has Amman as its capital?','JO',array['IL','JO','TR','LI']),
('2026-12-29','capital-lv','Which country has Riga as its capital?','LV',array['DK','GB','LV','NA']),
('2026-12-30','capital-az','Which country has Baku as its capital?','AZ',array['AZ','IQ','BH','LB']),
('2026-12-31','capital-bn','Which country has Bandar Seri Begawan as its capital?','BN',array['BN','BY','VN','PH']),
('2027-01-01','capital-kw','Which country has Kuwait City as its capital?','KW',array['SA','AE','KW','OM']),
('2027-01-02','capital-bg','Which country has Sofia as its capital?','BG',array['CU','ME','HR','BG']),
('2027-01-03','capital-cy','Which country has Nicosia as its capital?','CY',array['IT','CI','AD','CY']),
('2027-01-04','capital-ar','Which country has Buenos Aires as its capital?','AR',array['AR','PE','NE','UY']),
('2027-01-05','capital-bs','Which country has Nassau as its capital?','BS',array['LV','VC','BS','KN']),
('2027-01-06','capital-fj','Which country has Suva as its capital?','FJ',array['CR','VU','PG','FJ']),
('2027-01-07','capital-pa','Which country has Panama City as its capital?','PA',array['HN','PA','NI','SV']),
('2027-01-08','capital-lt','Which country has Vilnius as its capital?','LT',array['BA','LT','FI','LV']),
('2027-01-09','capital-qa','Which country has Doha as its capital?','QA',array['QA','KW','IQ','KH']),
('2027-01-10','capital-bh','Which country has Manama as its capital?','BH',array['QA','AM','IQ','BH']),
('2027-01-11','capital-tn','Which country has Tunis as its capital?','TN',array['TN','EG','ET','MA']),
('2027-01-12','capital-fm','Which country has Palikir as its capital?','FM',array['CM','FM','NR','KI']),
('2027-01-13','capital-mm','Which country has Naypyidaw as its capital?','MM',array['DE','MM','MY','SG']),
('2027-01-14','capital-ad','Which country has Andorra la Vella as its capital?','AD',array['SM','CY','IT','AD']),
('2027-01-15','capital-sl','Which country has Freetown as its capital?','SL',array['LR','NG','JP','SL']),
('2027-01-16','capital-mr','Which country has Nouakchott as its capital?','MR',array['NE','DE','GH','MR']),
('2027-01-17','capital-cv','Which country has Praia as its capital?','CV',array['BF','CV','HR','GM']),
('2027-01-18','capital-cf','Which country has Bangui as its capital?','CF',array['CG','CO','CF','ST']),
('2027-01-19','capital-ir','Which country has Tehran as its capital?','IR',array['AD','IR','NP','BT']),
('2027-01-20','capital-mx','Which country’s capital was built on the site of Tenochtitlan?','MX',array['MX','ML','US','CA']),
('2027-01-21','capital-ws','Which country has Apia as its capital?','WS',array['WS','TV','TT','TO']),
('2027-01-22','capital-vc','Which country has Kingstown as its capital?','VC',array['SE','VC','DO','TT']),
('2027-01-23','capital-cm','Which country has Yaoundé as its capital?','CM',array['TD','GQ','HR','CM']),
('2027-01-24','capital-bw','Which country has Gaborone as its capital?','BW',array['SZ','BW','NA','EE']),
('2027-01-25','capital-bi','Which country has Gitega as its capital?','BI',array['BI','KE','SR','ER']),
('2027-01-26','capital-ht','Which country has Port-au-Prince as its capital?','HT',array['TT','HT','CR','LC']),
('2027-01-27','capital-li','Which country has Vaduz as its capital?','LI',array['BE','LU','LI','TZ']),
('2027-01-28','capital-mg','Which country has Antananarivo as its capital?','MG',array['UG','TZ','MW','MG']),
('2027-01-29','capital-sz','Which country has Lobamba as its legislative capital and Mbabane as its administrative capital?','SZ',array['SZ','ZA','NA','LS']),
('2027-01-30','capital-mt','Which country has Valletta as its capital?','MT',array['MC','ES','MT','CY']),
('2027-01-31','capital-uz','Which country has Tashkent as its capital?','UZ',array['VU','KZ','UZ','KG']),
('2027-02-01','capital-pl','Which country has Warsaw as its capital?','PL',array['PL','KH','AT','CZ']),
('2027-02-02','capital-km','Which country has Moroni as its capital?','KM',array['KM','RW','TZ','UA']),
('2027-02-03','capital-cd','Which country has Kinshasa as its capital?','CD',array['CD','TD','ST','PK']),
('2027-02-04','capital-ml','Which country has Bamako as its capital?','ML',array['ML','CI','BF','DE']),
('2027-02-05','capital-zw','Which country has Harare as its capital?','ZW',array['GW','ZW','ZM','KE']),
('2027-02-06','capital-eg','Which country has Cairo as its capital?','EG',array['EG','ES','SD','MA']),
('2027-02-07','capital-ke','Which country has Nairobi as its capital?','KE',array['ZW','ZM','MV','KE']),
('2027-02-08','capital-dm','Which country has Roseau as its capital?','DM',array['DM','DO','BG','GD']),
('2027-02-09','capital-cl','Which country has Santiago as its capital?','CL',array['FM','CL','AR','PE']),
('2027-02-10','capital-ve','Which country has Caracas as its capital?','VE',array['MT','UY','PY','VE']),
('2027-02-11','capital-cu','Which country has Havana as its capital?','CU',array['NR','AG','CU','GD']),
('2027-02-12','capital-ba','Which country has Sarajevo as its capital?','BA',array['BA','RS','DE','HR']),
('2027-02-13','capital-ly','Which country has Tripoli as its capital?','LY',array['LY','EG','MA','PW']),
('2027-02-14','capital-er','Which country has Asmara as its capital?','ER',array['BI','ER','UG','SG']),
('2027-02-15','capital-sb','Which country has Honiara as its capital?','SB',array['FJ','PG','SB','RW']),
('2027-02-16','capital-sn','Which country has Dakar as its capital?','SN',array['SL','SN','GM','MR']),
('2027-02-17','capital-bz','Which country has Belmopan as its capital?','BZ',array['SV','HN','BZ','SZ']),
('2027-02-18','capital-cg','Which country has Brazzaville as its capital?','CG',array['QA','CD','CG','CF']),
('2027-02-19','capital-gn','Which country has Conakry as its capital?','GN',array['GN','BF','QA','CI']),
('2027-02-20','capital-rw','Which country has Kigali as its capital?','RW',array['ER','DZ','TZ','RW']),
('2027-02-21','capital-ec','Which country has Quito as its capital?','EC',array['EC','AR','MX','GY']),
('2027-02-22','capital-no','Which country has Oslo as its capital?','NO',array['NO','DK','GB','MV']),
('2027-02-23','capital-by','Which country has Minsk as its capital?','BY',array['UA','MD','BY','HT']),
('2027-02-24','capital-do','Which country has Santo Domingo as its capital?','DO',array['JM','LV','DO','BS']),
('2027-02-25','capital-sv','Which country has San Salvador as its capital?','SV',array['TH','BZ','HN','SV']),
('2027-02-26','capital-my','Which country has Kuala Lumpur as its capital?','MY',array['BN','MY','FM','SG']),
('2027-02-27','capital-is','Which country has Reykjavik as its capital?','IS',array['NO','IS','VA','DK']),
('2027-02-28','capital-br','Which country has Brasília as its capital?','BR',array['BR','SR','EC','MW']),
('2027-03-01','capital-vn','Which country has Hanoi as its capital?','VN',array['KH','MM','BN','VN']),
('2027-03-02','capital-tj','Which country has Dushanbe as its capital?','TJ',array['KZ','BE','TJ','TM']),
('2027-03-03','capital-fi','Which country has Helsinki as its capital?','FI',array['NO','LT','FI','GN']),
('2027-03-04','capital-co','Which country has Bogotá as its capital?','CO',array['AR','CM','CO','PY']),
('2027-03-05','capital-ga','Which country has Libreville as its capital?','GA',array['GN','AO','GQ','GA']),
('2027-03-06','capital-sa','Which country has Riyadh as its capital?','SA',array['IL','MU','JO','SA']),
('2027-03-07','capital-mv','Which country has Malé as its capital?','MV',array['BD','BT','NR','MV']),
('2027-03-08','capital-ru','Which country has Moscow as its capital?','RU',array['QA','RU','BY','UA']),
('2027-03-09','capital-py','Which country has Asunción as its capital?','PY',array['SR','PY','CO','WS']),
('2027-03-10','capital-pe','Which country has Lima as its capital?','PE',array['VE','GD','PE','PY']),
('2027-03-11','capital-lc','Which country has Castries as its capital?','LC',array['JM','LC','SZ','HT']),
('2027-03-12','capital-tl','Which country has Dili as its capital?','TL',array['VN','MX','SG','TL']),
('2027-03-13','capital-md','Which country has Chișinău as its capital?','MD',array['CN','MD','BY','RU']),
('2027-03-14','capital-ro','Which country has Bucharest as its capital?','RO',array['RS','RO','HR','AF']),
('2027-03-15','capital-dz','Which country has Algiers as its capital?','DZ',array['MA','TN','DZ','LC']),
('2027-03-16','capital-sg','Which island city-state at the southern tip of the Malay Peninsula serves as its own capital?','SG',array['TL','SG','PH','VN']),
('2027-03-17','capital-bj','Which country has Porto-Novo as its capital?','BJ',array['ML','CZ','BJ','GN']),
('2027-03-18','capital-pt','Which country has Lisbon as its capital?','PT',array['MT','CF','PT','IT']),
('2027-03-19','capital-ci','Which country has Yamoussoukro as its capital?','CI',array['BT','CI','SN','GM']),
('2027-03-20','capital-np','Which country has Kathmandu as its capital?','NP',array['BS','MV','NP','BD']),
('2027-03-21','capital-ps','Which state claims East Jerusalem as its capital and has its administrative centre in Ramallah?','PS',array['PS','IL','AZ','GE']),
('2027-03-22','capital-hn','Which country has Tegucigalpa as its capital?','HN',array['GT','PS','CR','HN']),
('2027-03-23','capital-cr','Which country has San José as its capital?','CR',array['HN','CR','KP','PA']),
('2027-03-24','capital-ca','Which country has Ottawa as its capital?','CA',array['CA','MX','US','SE']),
('2027-03-25','capital-sd','Which country has Khartoum as its capital?','SD',array['SR','EG','SD','DZ']),
('2027-03-26','capital-tr','Which country has Ankara as its capital?','TR',array['TR','SA','SY','VA']),
('2027-03-27','capital-bb','Which country has Bridgetown as its capital?','BB',array['KN','BW','JM','BB']),
('2027-03-28','capital-it','Which country has Rome as its capital?','IT',array['VA','IT','CY','JP']),
('2027-03-29','capital-om','Which country has Muscat as its capital?','OM',array['GE','PS','OM','SD']),
('2027-03-30','capital-mc','Monte Carlo is a district of which Mediterranean city-state that serves as its own capital?','MC',array['NL','FR','MC','BE']),
('2027-03-31','capital-es','Which country has Madrid as its capital?','ES',array['DE','IT','ES','MT']),
('2027-04-01','capital-nl','Which country has Amsterdam as its capital?','NL',array['NL','FR','PE','LU']),
('2027-04-02','capital-cn','Which country has Beijing as its capital?','CN',array['MX','MN','CN','KP']),
('2027-04-03','capital-ae','Which country has Abu Dhabi as its capital?','AE',array['AM','AE','DZ','IL']),
('2027-04-04','capital-bf','Which country has Ouagadougou as its capital?','BF',array['CI','MX','ML','BF']),
('2027-04-05','capital-nr','Which island country has no official capital and has government offices in Yaren District?','NR',array['MH','PW','NR','KI']),
('2027-04-06','capital-tm','Which country has Ashgabat as its capital?','TM',array['LI','UZ','TJ','TM']),
('2027-04-07','capital-jp','Which country has Tokyo as its capital?','JP',array['MN','JP','KP','IE']),
('2027-04-08','capital-et','Which country has Addis Ababa as its capital?','ET',array['ET','MG','BI','AE']),
('2027-04-09','capital-ki','Which country has South Tarawa as its capital?','KI',array['NR','KI','MN','PW']),
('2027-04-10','capital-ee','Which country has Tallinn as its capital?','EE',array['DK','SN','EE','FI']),
('2027-04-11','capital-mk','Which country has Skopje as its capital?','MK',array['BG','MK','SC','HR']),
('2027-04-12','capital-iq','Which country has Baghdad as its capital?','IQ',array['OM','LB','IQ','BI']),
('2027-04-13','capital-ua','Which country has Kyiv as its capital?','UA',array['GY','RU','BY','UA']),
('2027-04-14','capital-ne','Which country has Niamey as its capital?','NE',array['NE','NL','SN','CV']),
('2027-04-15','capital-cz','Which country has Prague as its capital?','CZ',array['CN','AT','CZ','SI']),
('2027-04-16','capital-ch','Bern is the federal city and de facto capital of which country?','CH',array['LI','CH','BE','AT']),
('2027-04-17','capital-se','Which country has Stockholm as its capital?','SE',array['DK','SE','DJ','IE']),
('2027-04-18','capital-kr','Which country has Seoul as its capital?','KR',array['KR','CN','PG','JP']),
('2027-04-19','capital-lr','Which country has Monrovia as its capital?','LR',array['BF','NZ','LR','BJ']),
('2027-04-20','capital-vu','Which country has Port Vila as its capital?','VU',array['PG','VU','GW','FJ']),
('2027-04-21','capital-gr','Which country has Athens as its capital?','GR',array['GR','TT','CY','ES']),
('2027-04-22','capital-sm','Which country’s capital sits on Monte Titano?','SM',array['MT','AD','ES','SM']),
('2027-04-23','capital-ao','Which country has Luanda as its capital?','AO',array['SS','AO','ME','CD']),
('2027-04-24','capital-au','Which country has Canberra as its capital?','AU',array['MN','NZ','AU','SV']),
('2027-04-25','capital-af','Which country has Kabul as its capital?','AF',array['AF','MY','NP','BD']),
('2027-04-26','capital-ie','Which country has Dublin as its capital?','IE',array['SZ','IE','DK','LV']),
('2027-04-27','capital-sr','Which country has Paramaribo as its capital?','SR',array['PE','SR','UY','LS']),
('2027-04-28','capital-gy','Which country has Georgetown as its capital?','GY',array['GY','CO','PE','MW']),
('2027-04-29','capital-gb','Which country has London as its capital?','GB',array['VN','GB','IE','NO']),
('2027-04-30','capital-in','Which country has New Delhi as its capital?','IN',array['IN','BD','AU','IR']),
('2027-05-01','capital-la','Which country has Vientiane as its capital?','LA',array['PH','KH','LA','PY']),
('2027-05-02','capital-pg','Which country has Port Moresby as its capital?','PG',array['GR','PG','FJ','SB']),
('2027-05-03','capital-ss','Which country has Juba as its capital?','SS',array['SS','RO','GA','GQ']),
('2027-05-04','capital-ph','Which country has Manila as its capital?','PH',array['SG','TL','GT','PH']),
('2027-05-05','capital-ls','Which country has Maseru as its capital?','LS',array['TV','LS','SZ','NA']),
('2027-05-06','capital-bo','Which country has Sucre as its constitutional capital?','BO',array['UY','BO','SR','BN']),
('2027-05-07','capital-gd','Which country has St. George''s as its capital?','GD',array['SS','TT','GD','AG']),
('2027-05-08','capital-lu','Which country has Luxembourg as its capital?','LU',array['LI','LU','DE','MC']),
('2027-05-09','capital-zm','Which country has Lusaka as its capital?','ZM',array['DJ','SR','ER','ZM']),
('2027-05-10','capital-nz','Which country has Wellington as its capital?','NZ',array['NZ','ZM','ZA','AU']),
('2027-05-11','capital-al','Which country has Tirana as its capital?','AL',array['AL','ME','ET','RO']),
('2027-05-12','capital-ni','Which country has Managua as its capital?','NI',array['GH','SV','NI','HN']),
('2027-05-13','capital-gm','Which country has Banjul as its capital?','GM',array['SN','TL','GM','LR']),
('2027-05-14','capital-mz','Which country has Maputo as its capital?','MZ',array['MZ','RW','UG','FR']),
('2027-05-15','capital-mw','Which country has Lilongwe as its capital?','MW',array['SO','MG','IE','MW']),
('2027-05-16','capital-pk','Which country has Islamabad as its capital?','PK',array['PK','IR','IS','NP']),
('2027-05-17','capital-tv','Which country has Funafuti as its capital?','TV',array['TV','TO','VE','WS']),
('2027-05-18','capital-ma','Which country has Rabat as its capital?','MA',array['MA','LY','BS','TN']),
('2027-05-19','capital-kp','Which country has Pyongyang as its capital?','KP',array['JP','LV','MN','KP']),
('2027-05-20','capital-so','Which country has Mogadishu as its capital?','SO',array['DJ','SO','LV','RW']),
('2027-05-21','capital-sc','Which country has Victoria as its capital?','SC',array['RW','MU','TR','SC']),
('2027-05-22','capital-sk','Which country has Bratislava as its capital?','SK',array['SK','SR','CZ','SI']),
('2027-05-23','capital-na','Which country has Windhoek as its capital?','NA',array['ZA','NA','SZ','BA']),
('2027-05-24','capital-ag','Which country has Saint John''s as its capital?','AG',array['JM','TT','AG','LC']),
('2027-05-25','capital-lk','Which country has Sri Jayawardenepura Kotte as its capital?','LK',array['LK','DE','IR','NP']),
('2027-05-26','capital-td','Which country has N''Djamena as its capital?','TD',array['GQ','CG','TD','MY']),
('2027-05-27','capital-id','Which country chose Nusantara on the island of Borneo as the site for its new capital?','ID',array['ID','BN','TH','PH']),
('2027-05-28','capital-me','Which country has Podgorica as its capital?','ME',array['MV','HR','BA','ME']),
('2027-05-29','capital-mu','Which country has Port Louis as its capital?','MU',array['MU','MZ','TL','ZM']),
('2027-05-30','capital-za','Which country has Cape Town as its legislative capital and Pretoria as its administrative capital?','ZA',array['LS','NA','SZ','ZA']),
('2027-05-31','capital-dj','Which country has Djibouti as its capital?','DJ',array['MZ','KE','DJ','UG']),
('2027-06-01','capital-rs','Which country has Belgrade as its capital?','RS',array['BG','ME','KN','RS']),
('2027-06-02','capital-il','Which country designates Jerusalem as its capital and holds sessions of the Knesset there?','IL',array['BH','GE','IL','AM']),
('2027-06-03','capital-tz','Which country has Dodoma as its capital?','TZ',array['TZ','LC','RW','UG']),
('2027-06-04','capital-kn','Which country has Basseterre as its capital?','KN',array['HT','KN','LC','NZ']),
('2027-06-05','capital-gh','Which country has Accra as its capital?','GH',array['BR','GH','GN','MR']),
('2027-06-06','capital-ye','Which country has Sana’a as its constitutional capital?','YE',array['YE','CD','SY','OM']);

create function wn_private.today_quiz() returns jsonb language sql stable security definer set search_path='' as $$
  select to_jsonb(q) from wn_private.quiz_schedule q where day = (now() at time zone 'UTC')::date
$$;
create function public.today_quiz() returns jsonb language sql stable security definer set search_path='' as $$
  select wn_private.today_quiz()
$$;

create function wn_private.submit_quiz(p_owner uuid, p_day date, p_choice text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
  u uuid := wn_private.require_user();
  q wn_private.quiz_schedule;
  picked text;
begin
  if p_owner is distinct from u or p_day is distinct from (now() at time zone 'UTC')::date then
    raise exception 'This quiz is no longer open';
  end if;
  select * into strict q from wn_private.quiz_schedule where day = p_day;
  if p_choice is null or not p_choice = any(q.options) then raise exception 'Invalid choice'; end if;
  insert into wn_private.quiz_attempts(user_id, day, choice) values(u, p_day, p_choice)
    on conflict (user_id,day) do nothing;
  select choice into strict picked from wn_private.quiz_attempts where user_id=u and day=p_day;
  return jsonb_build_object('day',p_day,'choice',picked,'correct',picked=q.answer);
end $$;
create function public.submit_quiz(p_owner uuid, p_day date, p_choice text) returns jsonb
language sql security invoker set search_path='' as $$ select wn_private.submit_quiz(p_owner,p_day,p_choice) $$;

create function wn_private.quiz_history(u uuid) returns jsonb language sql stable set search_path='' as $$
  select coalesce(jsonb_agg(jsonb_build_object('day',a.day,'choice',a.choice,'correct',a.choice=q.answer)
    order by a.day),'[]') from wn_private.quiz_attempts a join wn_private.quiz_schedule q using(day) where user_id=u
$$;
create function wn_private.quiz_standings() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  u uuid := wn_private.require_user();
  week_start date := date_trunc('week', now() at time zone 'UTC')::date;
  board jsonb;
begin
  with players as (
    select u as id, 'You' as name
    union all
    select p.id,p.display_name
    from public.wn_friendships f
    join public.wn_profiles p on p.id=case when f.user_low=u then f.user_high else f.user_low end
    where u in(f.user_low,f.user_high) and p.share_exploration
      and exists(select from public.wn_profiles me where me.id=u and me.share_exploration)
      and wn_private.are_friends(u,p.id) and not wn_private.community_restricted(p.id)
      and not wn_private.community_restricted(u)
  ), scores as (
    select p.id,p.name, count(*) filter(where a.choice=q.answer) as score
    from players p left join wn_private.quiz_attempts a on a.user_id=p.id and a.day>=week_start
      and a.day<week_start+7
    left join wn_private.quiz_schedule q on q.day=a.day
    group by p.id,p.name
  )
  select jsonb_agg(to_jsonb(s) order by s.score desc,s.name,s.id) into board from scores s;
  return jsonb_build_object('attempts',wn_private.quiz_history(u),'board',board);
end $$;
create function public.quiz_standings() returns jsonb language sql stable security invoker set search_path='' as $$
  select wn_private.quiz_standings()
$$;
revoke all on function wn_private.keep_quiz_slot(),wn_private.quiz_history(uuid),wn_private.today_quiz(),
  public.today_quiz(),wn_private.submit_quiz(uuid,date,text),public.submit_quiz(uuid,date,text),
  wn_private.quiz_standings(),public.quiz_standings() from public,anon,authenticated;
grant execute on function public.today_quiz(),wn_private.today_quiz() to anon,authenticated;
grant execute on function public.submit_quiz(uuid,date,text),wn_private.submit_quiz(uuid,date,text),
  public.quiz_standings(),wn_private.quiz_standings() to authenticated;

-- Preserve the existing export and include the owner's accepted answers.
alter function wn_private.export_my_data() rename to export_before_quiz;
revoke all on function wn_private.export_before_quiz() from public,anon,authenticated;
create function wn_private.export_my_data() returns jsonb language sql security definer set search_path='' as $$
  select wn_private.export_before_quiz() || jsonb_build_object('quiz',wn_private.quiz_history(wn_private.require_user()))
$$;
create or replace function public.export_my_data() returns jsonb language sql security invoker set search_path='' as $$
  select wn_private.export_my_data()
$$;
revoke all on function wn_private.export_my_data() from public,anon,authenticated;
grant execute on function wn_private.export_my_data() to authenticated;

notify pgrst,'reload schema';
commit;
