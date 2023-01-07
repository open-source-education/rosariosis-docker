-- phpMyAdmin SQL Dump
-- version 5.2.0
-- https://www.phpmyadmin.net/
--
-- Host: 192.168.0.24
-- Generation Time: Jan 07, 2023 at 05:42 PM
-- Server version: 5.7.39
-- PHP Version: 8.0.19

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `rosariosis`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`rosariosis_user`@`%` PROCEDURE `calc_cum_cr_gpa` (`mp_id` INTEGER, `s_id` INTEGER)   BEGIN
    UPDATE student_mp_stats
    SET cum_cr_weighted_factor = cr_weighted_factors/cr_credits,
        cum_cr_unweighted_factor = cr_unweighted_factors/cr_credits
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`rosariosis_user`@`%` PROCEDURE `calc_cum_gpa` (`mp_id` INTEGER, `s_id` INTEGER)   BEGIN
    UPDATE student_mp_stats
    SET cum_weighted_factor = sum_weighted_factors/gp_credits,
        cum_unweighted_factor = sum_unweighted_factors/gp_credits
    WHERE student_mp_stats.student_id = s_id and student_mp_stats.marking_period_id = mp_id;
END$$

CREATE DEFINER=`rosariosis_user`@`%` PROCEDURE `calc_gpa_mp` (`s_id` INTEGER, `mp_id` INTEGER)   BEGIN
    DECLARE oldrec integer;
    SELECT count(*) INTO oldrec FROM student_mp_stats WHERE student_id = s_id and marking_period_id = mp_id;
    IF oldrec > 0 THEN
    UPDATE student_mp_stats sms
    JOIN (
        select
        student_id,
        marking_period_id,
        sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
        sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
        sum(credit_attempted) as gp_credits,
        sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
        sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
        sum( case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades
        where student_id = s_id
        and marking_period_id = mp_id
        and not gp_scale = 0
        group by student_id, marking_period_id
    ) as rcg
    ON rcg.student_id = sms.student_id and rcg.marking_period_id = sms.marking_period_id
    SET
        sms.sum_weighted_factors = rcg.sum_weighted_factors,
        sms.sum_unweighted_factors = rcg.sum_unweighted_factors,
        sms.cr_weighted_factors = rcg.cr_weighted,
        sms.cr_unweighted_factors = rcg.cr_unweighted,
        sms.gp_credits = rcg.gp_credits,
        sms.cr_credits = rcg.cr_credits;
    ELSE
    INSERT INTO student_mp_stats (student_id, marking_period_id, sum_weighted_factors, sum_unweighted_factors, grade_level_short, cr_weighted_factors, cr_unweighted_factors, gp_credits, cr_credits)
        select
            srcg.student_id,
            srcg.marking_period_id,
            sum(weighted_gp*credit_attempted/gp_scale) as sum_weighted_factors,
            sum(unweighted_gp*credit_attempted/gp_scale) as sum_unweighted_factors,
            (select eg.short_name
                from enroll_grade eg, marking_periods mp
                where eg.student_id = s_id
                and eg.syear = mp.syear
                and eg.school_id = mp.school_id
                and eg.start_date <= mp.end_date
                and mp.marking_period_id = mp_id
                order by eg.start_date desc
                limit 1) as short_name,
            sum( case when class_rank = 'Y' THEN weighted_gp*credit_attempted/gp_scale END ) as cr_weighted,
            sum( case when class_rank = 'Y' THEN unweighted_gp*credit_attempted/gp_scale END ) as cr_unweighted,
            sum(credit_attempted) as gp_credits,
            sum(case when class_rank = 'Y' THEN credit_attempted END) as cr_credits
        from student_report_card_grades srcg
        where srcg.student_id = s_id and srcg.marking_period_id = mp_id and not srcg.gp_scale = 0
        group by srcg.student_id, srcg.marking_period_id, short_name;
    END IF;
END$$

CREATE DEFINER=`rosariosis_user`@`%` PROCEDURE `t_update_mp_stats` (`s_id` INTEGER, `mp_id` INTEGER)   BEGIN
    CALL calc_gpa_mp(s_id, mp_id);
    CALL calc_cum_gpa(mp_id, s_id);
    CALL calc_cum_cr_gpa(mp_id, s_id);
END$$

--
-- Functions
--
CREATE DEFINER=`rosariosis_user`@`%` FUNCTION `credit` (`cp_id` INTEGER, `mp_id` INTEGER) RETURNS DECIMAL(6,2)  BEGIN
    DECLARE course_detail_mp_id integer;
    DECLARE course_detail_mp varchar(3);
    DECLARE course_detail_credits numeric(6,2);
    DECLARE mp_detail_mp_id integer;
    DECLARE mp_detail_mp_type varchar(20);
    DECLARE val_mp_count integer;
    select marking_period_id,mp,credits into course_detail_mp_id,course_detail_mp,course_detail_credits from course_periods where course_period_id = cp_id;
    select marking_period_id,mp_type into mp_detail_mp_id,mp_detail_mp_type from marking_periods where marking_period_id = mp_id;
    IF course_detail_mp_id = mp_detail_mp_id THEN
        RETURN course_detail_credits;
    ELSEIF course_detail_mp = 'FY' AND mp_detail_mp_type = 'semester' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSEIF course_detail_mp = 'FY' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where grandparent_id = course_detail_mp_id group by grandparent_id;
    ELSEIF course_detail_mp = 'SEM' and mp_detail_mp_type = 'quarter' THEN
        select count(*) into val_mp_count from marking_periods where parent_id = course_detail_mp_id group by parent_id;
    ELSE
        RETURN course_detail_credits;
    END IF;
    IF val_mp_count > 0 THEN
        RETURN course_detail_credits/val_mp_count;
    ELSE
        RETURN course_detail_credits;
    END IF;
END$$

CREATE DEFINER=`rosariosis_user`@`%` FUNCTION `set_class_rank_mp` (`mp_id` INTEGER) RETURNS INT(11)  BEGIN
    update student_mp_stats sms
    JOIN (
        select mp.marking_period_id, sgm.student_id,
        (select count(*)+1
            from student_mp_stats sgm3
            where sgm3.cum_cr_weighted_factor > sgm.cum_cr_weighted_factor
            and sgm3.marking_period_id = mp.marking_period_id
            and sgm3.student_id in (select distinct sgm2.student_id
                from student_mp_stats sgm2, student_enrollment se2
                where sgm2.student_id = se2.student_id
                and sgm2.marking_period_id = mp.marking_period_id
                and se2.grade_id = se.grade_id)) as rank,
        (select count(*)
            from student_mp_stats sgm4
            where sgm4.marking_period_id = mp.marking_period_id
            and sgm4.student_id in (select distinct sgm5.student_id
                from student_mp_stats sgm5, student_enrollment se3
                where sgm5.student_id = se3.student_id
                and sgm5.marking_period_id = mp.marking_period_id
                and se3.grade_id = se.grade_id)) as class_size
        from student_enrollment se, student_mp_stats sgm, marking_periods mp
        where se.student_id = sgm.student_id
        and sgm.marking_period_id = mp.marking_period_id
        and mp.marking_period_id = mp_id
        and se.syear = mp.syear
        and not sgm.cum_cr_weighted_factor is null
    ) as rank
    ON sms.marking_period_id = rank.marking_period_id and sms.student_id = rank.student_id
    set sms.cum_rank = rank.rank, sms.class_size = rank.class_size;
    RETURN 1;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `access_log`
--

CREATE TABLE `access_log` (
  `syear` decimal(4,0) NOT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `login_time` datetime DEFAULT NULL,
  `ip_address` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `user_agent` text COLLATE utf8mb4_unicode_520_ci,
  `status` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_incomes`
--

CREATE TABLE `accounting_incomes` (
  `assigned_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_payments`
--

CREATE TABLE `accounting_payments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `staff_id` int(11) DEFAULT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `accounting_salaries`
--

CREATE TABLE `accounting_salaries` (
  `staff_id` int(11) NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address`
--

CREATE TABLE `address` (
  `address_id` int(11) NOT NULL,
  `house_no` decimal(5,0) DEFAULT NULL,
  `direction` varchar(2) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `street` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `apt` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `city` text COLLATE utf8mb4_unicode_520_ci,
  `state` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_street` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_city` text COLLATE utf8mb4_unicode_520_ci,
  `mail_state` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mail_zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `address` text COLLATE utf8mb4_unicode_520_ci,
  `mail_address` text COLLATE utf8mb4_unicode_520_ci,
  `phone` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `address`
--

INSERT INTO `address` (`address_id`, `house_no`, `direction`, `street`, `apt`, `zipcode`, `city`, `state`, `mail_street`, `mail_city`, `mail_state`, `mail_zipcode`, `address`, `mail_address`, `phone`, `created_at`, `updated_at`) VALUES
(0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'No Address', NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `address_fields`
--

CREATE TABLE `address_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `address_field_categories`
--

CREATE TABLE `address_field_categories` (
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `residence` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mailing` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendar`
--

CREATE TABLE `attendance_calendar` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `minutes` int(11) DEFAULT NULL,
  `block` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `calendar_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_calendars`
--

CREATE TABLE `attendance_calendars` (
  `school_id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `calendar_id` int(11) NOT NULL,
  `default_calendar` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_calendars`
--

INSERT INTO `attendance_calendars` (`school_id`, `title`, `syear`, `calendar_id`, `default_calendar`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, 'Main', '2022', 1, 'Y', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `attendance_codes`
--

CREATE TABLE `attendance_codes` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `state_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `table_name` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `attendance_codes`
--

INSERT INTO `attendance_codes` (`id`, `syear`, `school_id`, `title`, `short_name`, `type`, `state_code`, `default_code`, `table_name`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, 'Absent', 'A', 'teacher', 'A', NULL, 0, NULL, '2023-01-07 17:39:56', NULL),
(2, '2022', 1, 'Present', 'P', 'teacher', 'P', 'Y', 0, NULL, '2023-01-07 17:39:56', NULL),
(3, '2022', 1, 'Tardy', 'T', 'teacher', 'P', NULL, 0, NULL, '2023-01-07 17:39:56', NULL),
(4, '2022', 1, 'Excused Absence', 'E', 'official', 'A', NULL, 0, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `attendance_code_categories`
--

CREATE TABLE `attendance_code_categories` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_completed`
--

CREATE TABLE `attendance_completed` (
  `staff_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `table_name` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_day`
--

CREATE TABLE `attendance_day` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `minutes_present` int(11) DEFAULT NULL,
  `state_value` decimal(2,1) DEFAULT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `attendance_period`
--

CREATE TABLE `attendance_period` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `attendance_code` int(11) DEFAULT NULL,
  `attendance_teacher_code` int(11) DEFAULT NULL,
  `attendance_reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_fees`
--

CREATE TABLE `billing_fees` (
  `student_id` int(11) NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `waived_fee_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `billing_payments`
--

CREATE TABLE `billing_payments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `amount` decimal(14,2) NOT NULL,
  `payment_date` date DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `refunded_payment_id` int(11) DEFAULT NULL,
  `lunch_payment` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `calendar_events`
--

CREATE TABLE `calendar_events` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `school_date` date DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `config`
--

CREATE TABLE `config` (
  `school_id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `config_value` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `config`
--

INSERT INTO `config` (`school_id`, `title`, `config_value`, `created_at`, `updated_at`) VALUES
(0, 'LOGIN', 'No', '2023-01-07 17:39:56', NULL),
(0, 'VERSION', '10.6.3', '2023-01-07 17:39:56', NULL),
(0, 'TITLE', 'Rosario Student Information System', '2023-01-07 17:39:56', NULL),
(0, 'NAME', 'RosarioSIS', '2023-01-07 17:39:56', NULL),
(0, 'MODULES', 'a:13:{s:12:\"School_Setup\";b:1;s:8:\"Students\";b:1;s:5:\"Users\";b:1;s:10:\"Scheduling\";b:1;s:6:\"Grades\";b:1;s:10:\"Attendance\";b:1;s:11:\"Eligibility\";b:1;s:10:\"Discipline\";b:1;s:10:\"Accounting\";b:1;s:15:\"Student_Billing\";b:1;s:12:\"Food_Service\";b:1;s:9:\"Resources\";b:1;s:6:\"Custom\";b:1;}', '2023-01-07 17:39:56', NULL),
(0, 'PLUGINS', 'a:1:{s:6:\"Moodle\";b:0;}', '2023-01-07 17:39:56', NULL),
(0, 'THEME', 'FlatSIS', '2023-01-07 17:39:56', NULL),
(0, 'THEME_FORCE', NULL, '2023-01-07 17:39:56', NULL),
(0, 'CREATE_USER_ACCOUNT', NULL, '2023-01-07 17:39:56', NULL),
(0, 'CREATE_STUDENT_ACCOUNT', NULL, '2023-01-07 17:39:56', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_AUTOMATIC_ACTIVATION', NULL, '2023-01-07 17:39:56', NULL),
(0, 'CREATE_STUDENT_ACCOUNT_DEFAULT_SCHOOL', NULL, '2023-01-07 17:39:56', NULL),
(0, 'STUDENTS_EMAIL_FIELD', NULL, '2023-01-07 17:39:56', NULL),
(0, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2023-01-07 17:39:56', NULL),
(1, 'DISPLAY_NAME', 'CONCAT(FIRST_NAME,coalesce(NULLIF(CONCAT(\' \',MIDDLE_NAME,\' \'),\'  \'),\' \'),LAST_NAME)', '2023-01-07 17:39:56', NULL),
(0, 'LIMIT_EXISTING_CONTACTS_ADDRESSES', NULL, '2023-01-07 17:39:56', NULL),
(0, 'FAILED_LOGIN_LIMIT', '30', '2023-01-07 17:39:56', NULL),
(0, 'PASSWORD_STRENGTH', '1', '2023-01-07 17:39:56', NULL),
(0, 'FORCE_PASSWORD_CHANGE_ON_FIRST_LOGIN', NULL, '2023-01-07 17:39:56', NULL),
(0, 'GRADEBOOK_CONFIG_ADMIN_OVERRIDE', NULL, '2023-01-07 17:39:56', NULL),
(0, 'REMOVE_ACCESS_USERNAME_PREFIX_ADD', NULL, '2023-01-07 17:39:56', NULL),
(1, 'SCHOOL_SYEAR_OVER_2_YEARS', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'ATTENDANCE_FULL_DAY_MINUTES', '300', '2023-01-07 17:39:56', NULL),
(1, 'STUDENTS_USE_MAILING', NULL, '2023-01-07 17:39:56', NULL),
(1, 'CURRENCY', '$', '2023-01-07 17:39:56', NULL),
(1, 'DECIMAL_SEPARATOR', '.', '2023-01-07 17:39:56', NULL),
(1, 'THOUSANDS_SEPARATOR', ',', '2023-01-07 17:39:56', NULL),
(1, 'CLASS_RANK_CALCULATE_MPS', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `courses`
--

CREATE TABLE `courses` (
  `syear` decimal(4,0) NOT NULL,
  `course_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `grade_level` int(11) DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `course_details`
-- (See below for the actual view)
--
CREATE TABLE `course_details` (
`school_id` int(11)
,`syear` decimal(4,0)
,`marking_period_id` int(11)
,`subject_id` int(11)
,`course_id` int(11)
,`course_period_id` int(11)
,`teacher_id` int(11)
,`course_title` varchar(100)
,`cp_title` text
,`grade_scale_id` int(11)
,`mp` varchar(3)
,`credits` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `course_periods`
--

CREATE TABLE `course_periods` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `teacher_id` int(11) NOT NULL,
  `secondary_teacher_id` int(11) DEFAULT NULL,
  `room` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `total_seats` decimal(10,0) DEFAULT NULL,
  `filled_seats` decimal(10,0) DEFAULT NULL,
  `does_attendance` text COLLATE utf8mb4_unicode_520_ci,
  `does_honor_roll` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `does_class_rank` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `gender_restriction` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `house_restriction` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `availability` decimal(10,0) DEFAULT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `calendar_id` int(11) DEFAULT NULL,
  `half_day` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `does_breakoff` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `grade_scale_id` int(11) DEFAULT NULL,
  `credits` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_period_school_periods`
--

CREATE TABLE `course_period_school_periods` (
  `course_period_school_periods_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `period_id` int(11) NOT NULL,
  `days` varchar(7) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `course_subjects`
--

CREATE TABLE `course_subjects` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `subject_id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `custom_fields`
--

CREATE TABLE `custom_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `custom_fields`
--

INSERT INTO `custom_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'select', 'Gender', '0', 'Male\r\nFemale', 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000001, 'select', 'Ethnicity', '1', 'White, Non-Hispanic\r\nBlack, Non-Hispanic\r\nAmer. Indian or Alaskan Native\r\nAsian or Pacific Islander\r\nHispanic\r\nOther', 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000002, 'text', 'Common Name', '2', NULL, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000003, 'text', 'Social Security', '3', NULL, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000004, 'date', 'Birthdate', '4', NULL, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000005, 'select', 'Language', '5', 'English\r\nSpanish', 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000006, 'text', 'Physician', '6', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000007, 'text', 'Physician Phone', '7', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000008, 'text', 'Preferred Hospital', '8', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000009, 'textarea', 'Comments', '9', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000010, 'radio', 'Has Doctor\'s Note', '10', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000011, 'textarea', 'Doctor\'s Note Comments', '11', NULL, 2, NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_fields`
--

CREATE TABLE `discipline_fields` (
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `data_type` varchar(30) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `column_name` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_fields`
--

INSERT INTO `discipline_fields` (`id`, `title`, `short_name`, `data_type`, `column_name`, `created_at`, `updated_at`) VALUES
(1, 'Violation', '', 'multiple_checkbox', 'CATEGORY_1', '2023-01-07 17:39:56', NULL),
(2, 'Detention Assigned', '', 'multiple_radio', 'CATEGORY_2', '2023-01-07 17:39:56', NULL),
(3, 'Parents Contacted By Teacher', '', 'checkbox', 'CATEGORY_3', '2023-01-07 17:39:56', NULL),
(4, 'Parent Contacted by Administrator', '', 'text', 'CATEGORY_4', '2023-01-07 17:39:56', NULL),
(5, 'Suspensions (Office Only)', '', 'multiple_checkbox', 'CATEGORY_5', '2023-01-07 17:39:56', NULL),
(6, 'Comments', '', 'textarea', 'CATEGORY_6', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_field_usage`
--

CREATE TABLE `discipline_field_usage` (
  `id` int(11) NOT NULL,
  `discipline_field_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `discipline_field_usage`
--

INSERT INTO `discipline_field_usage` (`id`, `discipline_field_id`, `syear`, `school_id`, `title`, `select_options`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 3, '2022', 1, 'Parents Contacted by Teacher', '', '4', '2023-01-07 17:39:56', NULL),
(2, 4, '2022', 1, 'Parent Contacted by Administrator', '', '5', '2023-01-07 17:39:56', NULL),
(3, 6, '2022', 1, 'Comments', '', '6', '2023-01-07 17:39:56', NULL),
(4, 1, '2022', 1, 'Violation', 'Skipping Class\r\nProfanity, vulgarity, offensive language\r\nInsubordination (Refusal to Comply, Disrespectful Behavior)\r\nInebriated (Alcohol or Drugs)\r\nTalking out of Turn\r\nHarassment\r\nFighting\r\nPublic Display of Affection\r\nOther', '1', '2023-01-07 17:39:56', NULL),
(5, 2, '2022', 1, 'Detention Assigned', '10 Minutes\r\n20 Minutes\r\n30 Minutes\r\nDiscuss Suspension', '2', '2023-01-07 17:39:56', NULL),
(6, 5, '2022', 1, 'Suspensions (Office Only)', 'Half Day\r\nIn School Suspension\r\n1 Day\r\n2 Days\r\n3 Days\r\n5 Days\r\n7 Days\r\nExpulsion', '3', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `discipline_referrals`
--

CREATE TABLE `discipline_referrals` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `student_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `staff_id` int(11) DEFAULT NULL,
  `entry_date` date DEFAULT NULL,
  `referral_date` date DEFAULT NULL,
  `category_1` text COLLATE utf8mb4_unicode_520_ci,
  `category_2` text COLLATE utf8mb4_unicode_520_ci,
  `category_3` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `category_4` text COLLATE utf8mb4_unicode_520_ci,
  `category_5` text COLLATE utf8mb4_unicode_520_ci,
  `category_6` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility`
--

CREATE TABLE `eligibility` (
  `student_id` int(11) NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `school_date` date DEFAULT NULL,
  `period_id` int(11) DEFAULT NULL,
  `eligibility_code` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_activities`
--

CREATE TABLE `eligibility_activities` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `eligibility_activities`
--

INSERT INTO `eligibility_activities` (`id`, `syear`, `school_id`, `title`, `start_date`, `end_date`, `comment`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, 'Boy\'s Basketball', '2022-10-01', '2023-04-12', NULL, '2023-01-07 17:39:56', NULL),
(2, '2022', 1, 'Chess Team', '2022-09-03', '2023-06-05', NULL, '2023-01-07 17:39:56', NULL),
(3, '2022', 1, 'Girl\'s Basketball', '2022-10-01', '2023-04-12', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `eligibility_completed`
--

CREATE TABLE `eligibility_completed` (
  `staff_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `enroll_grade`
-- (See below for the actual view)
--
CREATE TABLE `enroll_grade` (
`id` int(11)
,`syear` decimal(4,0)
,`school_id` int(11)
,`student_id` int(11)
,`start_date` date
,`end_date` date
,`short_name` varchar(3)
,`title` varchar(50)
);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_accounts`
--

CREATE TABLE `food_service_accounts` (
  `account_id` int(11) NOT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_accounts`
--

INSERT INTO `food_service_accounts` (`account_id`, `balance`, `transaction_id`, `created_at`, `updated_at`) VALUES
(1, '0.00', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_categories`
--

CREATE TABLE `food_service_categories` (
  `category_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `menu_id` int(11) NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_categories`
--

INSERT INTO `food_service_categories` (`category_id`, `school_id`, `menu_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 'Lunch Items', '1', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_items`
--

CREATE TABLE `food_service_items` (
  `item_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `description` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `icon` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `price` decimal(9,2) NOT NULL,
  `price_reduced` decimal(9,2) DEFAULT NULL,
  `price_free` decimal(9,2) DEFAULT NULL,
  `price_staff` decimal(9,2) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_items`
--

INSERT INTO `food_service_items` (`item_id`, `school_id`, `short_name`, `sort_order`, `description`, `icon`, `price`, `price_reduced`, `price_free`, `price_staff`, `created_at`, `updated_at`) VALUES
(1, 1, 'HOTL', '1', 'Student Lunch', 'Lunch.png', '1.65', '0.40', '0.00', '2.35', '2023-01-07 17:39:56', NULL),
(2, 1, 'MILK', '2', 'Milk', 'Milk.png', '0.25', NULL, NULL, '0.50', '2023-01-07 17:39:56', NULL),
(3, 1, 'XTRA', '3', 'Extra', 'Sandwich.png', '0.50', NULL, NULL, '1.00', '2023-01-07 17:39:56', NULL),
(4, 1, 'PIZZA', '4', 'Extra Pizza', 'Pizza.png', '1.00', NULL, NULL, '1.00', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menus`
--

CREATE TABLE `food_service_menus` (
  `menu_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menus`
--

INSERT INTO `food_service_menus` (`menu_id`, `school_id`, `title`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'Lunch', '1', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_menu_items`
--

CREATE TABLE `food_service_menu_items` (
  `menu_item_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `menu_id` int(11) NOT NULL,
  `item_id` int(11) NOT NULL,
  `category_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `does_count` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_menu_items`
--

INSERT INTO `food_service_menu_items` (`menu_item_id`, `school_id`, `menu_id`, `item_id`, `category_id`, `sort_order`, `does_count`, `created_at`, `updated_at`) VALUES
(1, 1, 1, 1, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(2, 1, 1, 2, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(3, 1, 1, 3, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(4, 1, 1, 4, 1, NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_accounts`
--

CREATE TABLE `food_service_staff_accounts` (
  `staff_id` int(11) NOT NULL,
  `status` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `barcode` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `balance` decimal(9,2) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transactions`
--

CREATE TABLE `food_service_staff_transactions` (
  `transaction_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `seller_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_staff_transaction_items`
--

CREATE TABLE `food_service_staff_transaction_items` (
  `item_id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `amount` decimal(9,2) DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_student_accounts`
--

CREATE TABLE `food_service_student_accounts` (
  `student_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `status` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `barcode` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `food_service_student_accounts`
--

INSERT INTO `food_service_student_accounts` (`student_id`, `account_id`, `discount`, `status`, `barcode`, `created_at`, `updated_at`) VALUES
(1, 1, NULL, NULL, '1000001', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transactions`
--

CREATE TABLE `food_service_transactions` (
  `transaction_id` int(11) NOT NULL,
  `account_id` int(11) NOT NULL,
  `student_id` int(11) DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `balance` decimal(9,2) DEFAULT NULL,
  `timestamp` datetime DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `seller_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `food_service_transaction_items`
--

CREATE TABLE `food_service_transaction_items` (
  `item_id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `amount` decimal(9,2) DEFAULT NULL,
  `discount` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `description` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignments`
--

CREATE TABLE `gradebook_assignments` (
  `assignment_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `course_id` int(11) DEFAULT NULL,
  `assignment_type_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `assigned_date` date DEFAULT NULL,
  `due_date` date DEFAULT NULL,
  `points` int(11) NOT NULL,
  `description` longtext COLLATE utf8mb4_unicode_520_ci,
  `file` text COLLATE utf8mb4_unicode_520_ci,
  `default_points` int(11) DEFAULT NULL,
  `submission` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_assignment_types`
--

CREATE TABLE `gradebook_assignment_types` (
  `assignment_type_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `course_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `final_grade_percent` decimal(6,5) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `color` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_mp` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `gradebook_grades`
--

CREATE TABLE `gradebook_grades` (
  `student_id` int(11) NOT NULL,
  `period_id` int(11) DEFAULT NULL,
  `course_period_id` int(11) NOT NULL,
  `assignment_id` int(11) NOT NULL,
  `points` decimal(6,2) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `grades_completed`
--

CREATE TABLE `grades_completed` (
  `staff_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `history_marking_periods`
--

CREATE TABLE `history_marking_periods` (
  `parent_id` int(11) DEFAULT NULL,
  `mp_type` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `lunch_period`
--

CREATE TABLE `lunch_period` (
  `student_id` int(11) NOT NULL,
  `school_date` date NOT NULL,
  `period_id` int(11) NOT NULL,
  `attendance_code` int(11) DEFAULT NULL,
  `attendance_teacher_code` int(11) DEFAULT NULL,
  `attendance_reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `table_name` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Stand-in structure for view `marking_periods`
-- (See below for the actual view)
--
CREATE TABLE `marking_periods` (
`marking_period_id` int(11)
,`mp_source` varchar(7)
,`syear` decimal(4,0)
,`school_id` int(11)
,`mp_type` varchar(20)
,`title` varchar(50)
,`short_name` varchar(10)
,`sort_order` decimal(10,0)
,`parent_id` bigint(11)
,`grandparent_id` bigint(20)
,`start_date` date
,`end_date` date
,`post_start_date` date
,`post_end_date` date
,`does_grades` varchar(1)
,`does_comments` varchar(1)
);

-- --------------------------------------------------------

--
-- Table structure for table `moodlexrosario`
--

CREATE TABLE `moodlexrosario` (
  `column` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rosario_id` int(11) NOT NULL,
  `moodle_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `moodlexrosario`
--

INSERT INTO `moodlexrosario` (`column`, `rosario_id`, `moodle_id`, `created_at`, `updated_at`) VALUES
('staff_id', 1, 2, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `people`
--

CREATE TABLE `people` (
  `person_id` int(11) NOT NULL,
  `last_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `first_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_fields`
--

CREATE TABLE `people_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_field_categories`
--

CREATE TABLE `people_field_categories` (
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `custody` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `emergency` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `people_join_contacts`
--

CREATE TABLE `people_join_contacts` (
  `id` int(11) NOT NULL,
  `person_id` int(11) DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `value` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_notes`
--

CREATE TABLE `portal_notes` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `content` longtext COLLATE utf8mb4_unicode_520_ci,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int(11) DEFAULT NULL,
  `published_date` datetime DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text COLLATE utf8mb4_unicode_520_ci,
  `file_attached` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_polls`
--

CREATE TABLE `portal_polls` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `votes_number` int(11) DEFAULT NULL,
  `display_votes` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `published_user` int(11) DEFAULT NULL,
  `published_date` datetime DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `published_profiles` text COLLATE utf8mb4_unicode_520_ci,
  `students_teacher_id` int(11) DEFAULT NULL,
  `excluded_users` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `portal_poll_questions`
--

CREATE TABLE `portal_poll_questions` (
  `id` int(11) NOT NULL,
  `portal_poll_id` int(11) NOT NULL,
  `question` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `type` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `options` text COLLATE utf8mb4_unicode_520_ci,
  `votes` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `profile_exceptions`
--

CREATE TABLE `profile_exceptions` (
  `profile_id` int(11) NOT NULL,
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `can_use` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `can_edit` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `profile_exceptions`
--

INSERT INTO `profile_exceptions` (`profile_id`, `modname`, `can_use`, `can_edit`, `created_at`, `updated_at`) VALUES
(0, 'Attendance/DailySummary.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Attendance/StudentSummary.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Custom/Registration.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Eligibility/Student.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Eligibility/StudentList.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Food_Service/Accounts.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Food_Service/DailyMenus.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Food_Service/MenuItems.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Food_Service/Statements.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/FinalGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/GPARankList.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/ProgressReports.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/ReportCards.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/StudentAssignments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/StudentGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Grades/Transcripts.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Resources/Resources.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Scheduling/Courses.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Scheduling/Requests.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Scheduling/Schedule.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'School_Setup/Calendar.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'School_Setup/Schools.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Student_Billing/StudentFees.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Students/Student.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Students/Student.php&category_id=1', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Students/Student.php&category_id=3', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(0, 'Users/Preferences.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(1, 'Accounting/DailyTransactions.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/Expenses.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/Incomes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/Salaries.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/StaffBalances.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/StaffPayments.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Accounting/Statements.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/AddAbsences.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/Administration.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/AttendanceCodes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/DailySummary.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/DuplicateAttendance.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/FixDailyAttendance.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/Percent.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Attendance/TeacherCompletion.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Custom/AttendanceSummary.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Custom/CreateParents.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Custom/MyReport.php', NULL, NULL, '2023-01-07 17:39:56', NULL),
(1, 'Custom/NotifyParents.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Custom/Registration.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Custom/RemoveAccess.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/CategoryBreakdown.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/CategoryBreakdownTime.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/DisciplineForm.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/MakeReferral.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/ReferralForm.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/ReferralLog.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/Referrals.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Discipline/StudentFieldBreakdown.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/Activities.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/AddActivity.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/EntryTimes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/Student.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/StudentList.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Eligibility/TeacherCompletion.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Accounts.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/ActivityReport.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/DailyMenus.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Kiosk.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/MenuItems.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/MenuReports.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Menus.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Reminders.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/ServeMenus.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Statements.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/Transactions.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Food_Service/TransactionsReport.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/Configuration.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/EditHistoryMarkingPeriods.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/EditReportCardGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/FinalGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/FixGPA.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/GPARankList.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/GradeBreakdown.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/HonorRoll.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/MassCreateAssignments.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/ReportCardCommentCodes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/ReportCardComments.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/ReportCardGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/ReportCards.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/StudentGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/TeacherCompletion.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Grades/Transcripts.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Resources/Resources.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/AddDrop.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/Courses.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/IncompleteSchedules.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/MassDrops.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/MassRequests.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/MassSchedule.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/PrintClassLists.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/PrintClassPictures.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/PrintRequests.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/PrintSchedules.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/Requests.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/RequestsReport.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/Schedule.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/Scheduler.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Scheduling/ScheduleReport.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/AccessLog.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/Calendar.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/Configuration.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/CopySchool.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/DatabaseBackup.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/GradeLevels.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/MarkingPeriods.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/Periods.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/PortalNotes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/PortalPolls.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/Rollover.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/SchoolFields.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'School_Setup/Schools.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/DailyTransactions.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/Fees.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/MassAssignFees.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/MassAssignPayments.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/Statements.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/StudentBalances.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/StudentFees.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/StudentPayments.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Student_Billing/StudentPayments.php&modfunc=remove', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/AddDrop.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/AddUsers.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/AdvancedReport.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/AssignOtherInfo.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/EnrollmentCodes.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Letters.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/PrintStudentInfo.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Student.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Student.php&category_id=1', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Student.php&category_id=2', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Student.php&category_id=3', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/Student.php&include=General_Info&student_id=new', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/StudentBreakdown.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/StudentFields.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Students/StudentLabels.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/AddStudents.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/Exceptions.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/Preferences.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/Profiles.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Attendance/TakeAttendance.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Eligibility/EnterEligibility.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/AnomalousGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/Grades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/InputFinalGrades.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/TeacherPrograms.php&include=Grades/ProgressReports.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&category_id=1', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&category_id=1&schools', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&category_id=1&user_profile', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&category_id=2', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&category_id=3', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/User.php&staff_id=new', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(1, 'Users/UserFields.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Accounting/Salaries.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Accounting/StaffPayments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Accounting/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Attendance/DailySummary.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Attendance/TakeAttendance.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Discipline/MakeReferral.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Discipline/Referrals.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Eligibility/EnterEligibility.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Food_Service/Accounts.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Food_Service/DailyMenus.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Food_Service/MenuItems.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Food_Service/Statements.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/AnomalousGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/Assignments-new.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/Assignments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/Configuration.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/FinalGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/GradebookBreakdown.php', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Grades/Grades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/InputFinalGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/ProgressReports.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/ReportCardCommentCodes.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/ReportCardComments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/ReportCardGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/ReportCards.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Grades/StudentGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Resources/Resources.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Scheduling/Courses.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Scheduling/PrintClassLists.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Scheduling/Schedule.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'School_Setup/Calendar.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'School_Setup/Schools.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/AddUsers.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/AdvancedReport.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/Letters.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/Student.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/Student.php&category_id=1', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/Student.php&category_id=3', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Students/Student.php&category_id=4', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Students/StudentLabels.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Users/Preferences.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Users/User.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Users/User.php&category_id=1', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Users/User.php&category_id=2', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, 'Users/User.php&category_id=3', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Attendance/DailySummary.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Custom/Registration.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Eligibility/Student.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Eligibility/StudentList.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Food_Service/Accounts.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Food_Service/DailyMenus.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Food_Service/MenuItems.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Food_Service/Statements.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/FinalGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/GPARankList.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/ProgressReports.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/ReportCards.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/StudentAssignments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/StudentGrades.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Grades/Transcripts.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Resources/Resources.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Scheduling/Courses.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Scheduling/PrintClassPictures.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Scheduling/PrintSchedules.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Scheduling/Requests.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Scheduling/Schedule.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'School_Setup/Calendar.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'School_Setup/MarkingPeriods.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'School_Setup/Schools.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Student_Billing/DailyTransactions.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Student_Billing/Statements.php&_ROSARIO_PDF', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Student_Billing/StudentFees.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Student_Billing/StudentPayments.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Students/Student.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Students/Student.php&category_id=1', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Students/Student.php&category_id=3', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Users/Preferences.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Users/User.php', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Users/User.php&category_id=1', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Users/User.php&category_id=2', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, 'Users/User.php&category_id=3', 'Y', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_config`
--

CREATE TABLE `program_config` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `program` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `program_config`
--

INSERT INTO `program_config` (`syear`, `school_id`, `program`, `title`, `value`, `created_at`, `updated_at`) VALUES
('2022', 1, 'eligibility', 'START_DAY', '1', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'START_HOUR', '23', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'START_MINUTE', '30', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'START_M', 'PM', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'END_DAY', '5', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'END_HOUR', '23', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'END_MINUTE', '30', '2023-01-07 17:39:56', NULL),
('2022', 1, 'eligibility', 'END_M', 'PM', '2023-01-07 17:39:56', NULL),
('2022', 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_BEFORE', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'attendance', 'ATTENDANCE_EDIT_DAYS_AFTER', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_DOES_LETTER_PERCENT', '0', '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_HIDE_NON_ATTENDANCE_COMMENT', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_TEACHER_ALLOW_EDIT', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_GRADEBOOK_TEACHER_ALLOW_EDIT', 'Y', '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_DO_STATS_STUDENTS_PARENTS', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'grades', 'GRADES_DO_STATS_ADMIN_TEACHERS', 'Y', '2023-01-07 17:39:56', NULL),
('2022', 1, 'students', 'STUDENTS_USE_BUS', 'Y', '2023-01-07 17:39:56', NULL),
('2022', 1, 'students', 'STUDENTS_USE_CONTACT', 'Y', '2023-01-07 17:39:56', NULL),
('2022', 1, 'students', 'STUDENTS_SEMESTER_COMMENTS', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'moodle', 'MOODLE_URL', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'moodle', 'MOODLE_TOKEN', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'moodle', 'MOODLE_PARENT_ROLE_ID', NULL, '2023-01-07 17:39:56', NULL),
('2022', 1, 'food_service', 'FOOD_SERVICE_BALANCE_WARNING', '5', '2023-01-07 17:39:56', NULL),
('2022', 1, 'food_service', 'FOOD_SERVICE_BALANCE_MINIMUM', '-40', '2023-01-07 17:39:56', NULL),
('2022', 1, 'food_service', 'FOOD_SERVICE_BALANCE_TARGET', '19', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `program_user_config`
--

CREATE TABLE `program_user_config` (
  `user_id` int(11) NOT NULL,
  `program` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `value` longtext COLLATE utf8mb4_unicode_520_ci,
  `school_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comments`
--

CREATE TABLE `report_card_comments` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_id` int(11) DEFAULT NULL,
  `category_id` int(11) DEFAULT NULL,
  `scale_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_comments`
--

INSERT INTO `report_card_comments` (`id`, `syear`, `school_id`, `course_id`, `category_id`, `scale_id`, `sort_order`, `title`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, NULL, NULL, NULL, '1', '^n Fails to Meet Course Requirements', '2023-01-07 17:39:56', NULL),
(2, '2022', 1, NULL, NULL, NULL, '2', '^n Comes to ^s Class Unprepared', '2023-01-07 17:39:56', NULL),
(3, '2022', 1, NULL, NULL, NULL, '3', '^n Exerts Positive Influence in Class', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_categories`
--

CREATE TABLE `report_card_comment_categories` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `course_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `color` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_codes`
--

CREATE TABLE `report_card_comment_codes` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `scale_id` int(11) NOT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_comment_code_scales`
--

CREATE TABLE `report_card_comment_code_scales` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(25) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `comment` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grades`
--

CREATE TABLE `report_card_grades` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `gpa_value` decimal(7,2) DEFAULT NULL,
  `break_off` decimal(7,2) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `grade_scale_id` int(11) DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grades`
--

INSERT INTO `report_card_grades` (`id`, `syear`, `school_id`, `title`, `sort_order`, `gpa_value`, `break_off`, `comment`, `grade_scale_id`, `unweighted_gp`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, 'A+', '1', '4.00', '97.00', 'Consistently superior', 1, NULL, '2023-01-07 17:39:56', NULL),
(2, '2022', 1, 'A', '2', '4.00', '93.00', 'Superior', 1, NULL, '2023-01-07 17:39:56', NULL),
(3, '2022', 1, 'A-', '3', '3.75', '90.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(4, '2022', 1, 'B+', '4', '3.50', '87.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(5, '2022', 1, 'B', '5', '3.00', '83.00', 'Above average', 1, NULL, '2023-01-07 17:39:56', NULL),
(6, '2022', 1, 'B-', '6', '2.75', '80.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(7, '2022', 1, 'C+', '7', '2.50', '77.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(8, '2022', 1, 'C', '8', '2.00', '73.00', 'Average', 1, NULL, '2023-01-07 17:39:56', NULL),
(9, '2022', 1, 'C-', '9', '1.75', '70.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(10, '2022', 1, 'D+', '10', '1.50', '67.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(11, '2022', 1, 'D', '11', '1.00', '63.00', 'Below average', 1, NULL, '2023-01-07 17:39:56', NULL),
(12, '2022', 1, 'D-', '12', '0.75', '60.00', NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
(13, '2022', 1, 'F', '13', '0.00', '0.00', 'Failing', 1, NULL, '2023-01-07 17:39:56', NULL),
(14, '2022', 1, 'I', '14', '0.00', '0.00', 'Incomplete', 1, NULL, '2023-01-07 17:39:56', NULL),
(15, '2022', 1, 'N/A', '15', '0.00', NULL, NULL, 1, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `report_card_grade_scales`
--

CREATE TABLE `report_card_grade_scales` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `hhr_gpa_value` decimal(7,2) DEFAULT NULL,
  `hr_gpa_value` decimal(7,2) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `gp_scale` decimal(7,2) NOT NULL,
  `gp_passing_value` decimal(7,2) NOT NULL,
  `hrs_gpa_value` decimal(7,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `report_card_grade_scales`
--

INSERT INTO `report_card_grade_scales` (`id`, `syear`, `school_id`, `title`, `comment`, `hhr_gpa_value`, `hr_gpa_value`, `sort_order`, `rollover_id`, `gp_scale`, `gp_passing_value`, `hrs_gpa_value`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, 'Main', NULL, NULL, NULL, '1', NULL, '4.00', '0.00', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `resources`
--

CREATE TABLE `resources` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `link` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `resources`
--

INSERT INTO `resources` (`id`, `school_id`, `title`, `link`, `created_at`, `updated_at`) VALUES
(1, 1, 'Print Handbook', 'Help.php', '2023-01-07 17:39:56', NULL),
(2, 1, 'Quick Setup Guide', 'https://www.rosariosis.org/quick-setup-guide/', '2023-01-07 17:39:56', NULL),
(3, 1, 'Forum', 'https://www.rosariosis.org/forum/', '2023-01-07 17:39:56', NULL),
(4, 1, 'Contribute', 'https://www.rosariosis.org/contribute/', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `schedule`
--

CREATE TABLE `schedule` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date DEFAULT NULL,
  `modified_date` date DEFAULT NULL,
  `modified_by` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `scheduler_lock` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schedule_requests`
--

CREATE TABLE `schedule_requests` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `request_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `subject_id` int(11) DEFAULT NULL,
  `course_id` int(11) DEFAULT NULL,
  `marking_period_id` int(11) DEFAULT NULL,
  `priority` int(11) DEFAULT NULL,
  `with_teacher_id` int(11) DEFAULT NULL,
  `not_teacher_id` int(11) DEFAULT NULL,
  `with_period_id` int(11) DEFAULT NULL,
  `not_period_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `schools`
--

CREATE TABLE `schools` (
  `syear` decimal(4,0) NOT NULL,
  `id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `address` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `city` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `state` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `zipcode` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `phone` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `principal` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `www_address` text COLLATE utf8mb4_unicode_520_ci,
  `school_number` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `short_name` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `reporting_gp_scale` decimal(10,3) DEFAULT NULL,
  `number_days_rotation` decimal(1,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `schools`
--

INSERT INTO `schools` (`syear`, `id`, `title`, `address`, `city`, `state`, `zipcode`, `phone`, `principal`, `www_address`, `school_number`, `short_name`, `reporting_gp_scale`, `number_days_rotation`, `created_at`, `updated_at`) VALUES
('2022', 1, 'Default School', '500 S. Street St.', 'Springfield', 'IL', '62704', NULL, 'Mr. Principal', 'www.rosariosis.org', NULL, NULL, '4.000', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_fields`
--

CREATE TABLE `school_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `school_gradelevels`
--

CREATE TABLE `school_gradelevels` (
  `id` int(11) NOT NULL,
  `school_id` int(11) NOT NULL,
  `short_name` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `next_grade_id` int(11) DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_gradelevels`
--

INSERT INTO `school_gradelevels` (`id`, `school_id`, `short_name`, `title`, `next_grade_id`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, 1, 'KG', 'Kindergarten', 2, '1', '2023-01-07 17:39:56', NULL),
(2, 1, '01', '1st', 3, '2', '2023-01-07 17:39:56', NULL),
(3, 1, '02', '2nd', 4, '3', '2023-01-07 17:39:56', NULL),
(4, 1, '03', '3rd', 5, '4', '2023-01-07 17:39:56', NULL),
(5, 1, '04', '4th', 6, '5', '2023-01-07 17:39:56', NULL),
(6, 1, '05', '5th', 7, '6', '2023-01-07 17:39:56', NULL),
(7, 1, '06', '6th', 8, '7', '2023-01-07 17:39:56', NULL),
(8, 1, '07', '7th', 9, '8', '2023-01-07 17:39:56', NULL),
(9, 1, '08', '8th', NULL, '9', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_marking_periods`
--

CREATE TABLE `school_marking_periods` (
  `marking_period_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `mp` varchar(3) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `school_id` int(11) NOT NULL,
  `parent_id` int(11) DEFAULT NULL,
  `title` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `post_start_date` date DEFAULT NULL,
  `post_end_date` date DEFAULT NULL,
  `does_grades` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `does_comments` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_marking_periods`
--

INSERT INTO `school_marking_periods` (`marking_period_id`, `syear`, `mp`, `school_id`, `parent_id`, `title`, `short_name`, `sort_order`, `start_date`, `end_date`, `post_start_date`, `post_end_date`, `does_grades`, `does_comments`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, '2022', 'FY', 1, NULL, 'Full Year', 'FY', '1', '2022-06-14', '2023-06-12', NULL, NULL, NULL, NULL, NULL, '2023-01-07 17:39:56', NULL),
(2, '2022', 'SEM', 1, 1, 'Semester 1', 'S1', '1', '2022-06-14', '2022-12-31', '2022-12-28', '2022-12-31', NULL, NULL, NULL, '2023-01-07 17:39:56', NULL),
(3, '2022', 'SEM', 1, 1, 'Semester 2', 'S2', '2', '2023-01-01', '2023-06-12', '2023-06-11', '2023-06-12', NULL, NULL, NULL, '2023-01-07 17:39:56', NULL),
(4, '2022', 'QTR', 1, 2, 'Quarter 1', 'Q1', '1', '2022-06-14', '2022-09-13', '2022-09-11', '2022-09-13', 'Y', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(5, '2022', 'QTR', 1, 2, 'Quarter 2', 'Q2', '2', '2022-09-14', '2022-12-31', '2022-12-28', '2022-12-31', 'Y', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(6, '2022', 'QTR', 1, 3, 'Quarter 3', 'Q3', '3', '2023-01-01', '2023-03-14', '2023-03-12', '2023-03-14', 'Y', 'Y', NULL, '2023-01-07 17:39:56', NULL),
(7, '2022', 'QTR', 1, 3, 'Quarter 4', 'Q4', '4', '2023-03-15', '2023-06-12', '2023-06-11', '2023-06-12', 'Y', 'Y', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `school_periods`
--

CREATE TABLE `school_periods` (
  `period_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `length` int(11) DEFAULT NULL,
  `start_time` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `end_time` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `block` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `attendance` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `school_periods`
--

INSERT INTO `school_periods` (`period_id`, `syear`, `school_id`, `sort_order`, `title`, `short_name`, `length`, `start_time`, `end_time`, `block`, `attendance`, `rollover_id`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, '1', 'Full Day', 'FD', 300, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(2, '2022', 1, '2', 'Half Day AM', 'AM', 150, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(3, '2022', 1, '3', 'Half Day PM', 'PM', 150, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(4, '2022', 1, '4', 'Period 1', '01', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(5, '2022', 1, '5', 'Period 2', '02', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(6, '2022', 1, '6', 'Period 3', '03', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(7, '2022', 1, '7', 'Period 4', '04', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(8, '2022', 1, '8', 'Period 5', '05', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(9, '2022', 1, '9', 'Period 6', '06', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(10, '2022', 1, '10', 'Period 7', '07', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL),
(11, '2022', 1, '11', 'Period 8', '08', 50, NULL, NULL, NULL, 'Y', NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff`
--

CREATE TABLE `staff` (
  `syear` decimal(4,0) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `current_school_id` int(11) DEFAULT NULL,
  `title` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `first_name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `last_name` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name_suffix` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `password` varchar(106) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `email` varchar(255) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `custom_200000001` text COLLATE utf8mb4_unicode_520_ci,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `homeroom` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `schools` varchar(150) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int(11) DEFAULT NULL,
  `profile_id` int(11) DEFAULT NULL,
  `rollover_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff`
--

INSERT INTO `staff` (`syear`, `staff_id`, `current_school_id`, `title`, `first_name`, `last_name`, `middle_name`, `name_suffix`, `username`, `password`, `email`, `custom_200000001`, `profile`, `homeroom`, `schools`, `last_login`, `failed_login`, `profile_id`, `rollover_id`, `created_at`, `updated_at`) VALUES
('2022', 1, 1, NULL, 'Admin', 'Administrator', 'A', NULL, 'admin', '$6$dc51290a001671c6$97VSmw.Qu9sL6vpctFh62/YIbbR6b3DstJJxPXal2OndrtFszsxmVhdQaV2mJvb6Z38sPACXqDDQ7/uquwadd.', NULL, NULL, 'admin', NULL, ',1,', NULL, NULL, 1, NULL, '2023-01-07 17:39:56', NULL),
('2022', 2, 1, NULL, 'Teach', 'Teacher', 'T', NULL, 'teacher', '$6$cf0dc4c40d38891f$FqKT6nlTer3ujAf8CcQi6ABIEtlow0Va2p6HYh.M6eGWUfpgLr/pfrSwdIcTlV1LDxLg52puVETGMCYKL3vOo/', NULL, NULL, 'teacher', NULL, ',1,', NULL, NULL, 2, NULL, '2023-01-07 17:39:56', NULL),
('2022', 3, 1, NULL, 'Parent', 'Parent', 'P', NULL, 'parent', '$6$947c923597601364$Kgbb0Ey3lYTYnqM66VkFRgJVFDW48cBAfNF7t0CVjokL7drcEFId61whqpLrRI1w0q2J2VPfg86Obaf1tG2Ng1', NULL, NULL, 'parent', NULL, NULL, NULL, NULL, 3, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff_exceptions`
--

CREATE TABLE `staff_exceptions` (
  `user_id` int(11) NOT NULL,
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `can_use` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `can_edit` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `staff_fields`
--

CREATE TABLE `staff_fields` (
  `id` int(11) NOT NULL,
  `type` varchar(10) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `select_options` text COLLATE utf8mb4_unicode_520_ci,
  `category_id` int(11) DEFAULT NULL,
  `required` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_selection` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_fields`
--

INSERT INTO `staff_fields` (`id`, `type`, `title`, `sort_order`, `select_options`, `category_id`, `required`, `default_selection`, `created_at`, `updated_at`) VALUES
(200000000, 'text', 'Email Address', '0', NULL, 1, NULL, NULL, '2023-01-07 17:39:56', NULL),
(200000001, 'text', 'Phone Number', '1', NULL, 1, NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `staff_field_categories`
--

CREATE TABLE `staff_field_categories` (
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `admin` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `teacher` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `parent` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `none` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `staff_field_categories`
--

INSERT INTO `staff_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `admin`, `teacher`, `parent`, `none`, `created_at`, `updated_at`) VALUES
(1, 'General Info', '1', NULL, NULL, 'Y', 'Y', 'Y', 'Y', '2023-01-07 17:39:56', NULL),
(2, 'Schedule', '2', NULL, NULL, NULL, 'Y', NULL, NULL, '2023-01-07 17:39:56', NULL),
(3, 'Food Service', '3', NULL, 'Food_Service/User', 'Y', 'Y', NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

CREATE TABLE `students` (
  `student_id` int(11) NOT NULL,
  `last_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `first_name` varchar(50) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `middle_name` varchar(50) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `name_suffix` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `username` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `password` varchar(106) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `last_login` datetime DEFAULT NULL,
  `failed_login` int(11) DEFAULT NULL,
  `custom_200000000` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000001` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000002` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000003` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000004` date DEFAULT NULL,
  `custom_200000005` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000006` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000007` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000008` text COLLATE utf8mb4_unicode_520_ci,
  `custom_200000009` longtext COLLATE utf8mb4_unicode_520_ci,
  `custom_200000010` char(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `custom_200000011` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `students`
--

INSERT INTO `students` (`student_id`, `last_name`, `first_name`, `middle_name`, `name_suffix`, `username`, `password`, `last_login`, `failed_login`, `custom_200000000`, `custom_200000001`, `custom_200000002`, `custom_200000003`, `custom_200000004`, `custom_200000005`, `custom_200000006`, `custom_200000007`, `custom_200000008`, `custom_200000009`, `custom_200000010`, `custom_200000011`, `created_at`, `updated_at`) VALUES
(1, 'Student', 'Student', 'S', NULL, 'student', '$6$f03d507b27b8b9ff$WKtYRdFZGNjRKUr4btzq/p90hbKRAyB8HmrZpgpUhbAh.GtOCveXtXt43IaEDZJ31rVUYZ7ID8xPgKkCiRyzZ1', NULL, NULL, 'Male', 'White, Non-Hispanic', 'Bug', NULL, '2015-12-04', 'English', NULL, NULL, NULL, NULL, NULL, NULL, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `students_join_address`
--

CREATE TABLE `students_join_address` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `address_id` int(11) NOT NULL,
  `contact_seq` decimal(10,0) DEFAULT NULL,
  `gets_mail` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `primary_residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `legal_residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `am_bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `pm_bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `mailing` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `residence` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus_pickup` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `bus_dropoff` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_people`
--

CREATE TABLE `students_join_people` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `person_id` int(11) NOT NULL,
  `address_id` int(11) DEFAULT NULL,
  `custody` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `emergency` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `student_relation` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students_join_users`
--

CREATE TABLE `students_join_users` (
  `student_id` int(11) NOT NULL,
  `staff_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `students_join_users`
--

INSERT INTO `students_join_users` (`student_id`, `staff_id`, `created_at`, `updated_at`) VALUES
(1, 3, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_assignments`
--

CREATE TABLE `student_assignments` (
  `assignment_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `data` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_eligibility_activities`
--

CREATE TABLE `student_eligibility_activities` (
  `syear` decimal(4,0) DEFAULT NULL,
  `student_id` int(11) NOT NULL,
  `activity_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment`
--

CREATE TABLE `student_enrollment` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `grade_id` int(11) DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `end_date` date DEFAULT NULL,
  `enrollment_code` int(11) DEFAULT NULL,
  `drop_code` int(11) DEFAULT NULL,
  `next_school` int(11) DEFAULT NULL,
  `calendar_id` int(11) DEFAULT NULL,
  `last_school` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment`
--

INSERT INTO `student_enrollment` (`id`, `syear`, `school_id`, `student_id`, `grade_id`, `start_date`, `end_date`, `enrollment_code`, `drop_code`, `next_school`, `calendar_id`, `last_school`, `created_at`, `updated_at`) VALUES
(1, '2022', 1, 1, 7, '2022-06-10', NULL, 3, NULL, 1, 1, 1, '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_enrollment_codes`
--

CREATE TABLE `student_enrollment_codes` (
  `id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `short_name` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `type` varchar(4) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `default_code` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_enrollment_codes`
--

INSERT INTO `student_enrollment_codes` (`id`, `syear`, `title`, `short_name`, `type`, `default_code`, `sort_order`, `created_at`, `updated_at`) VALUES
(1, '2022', 'Moved from District', 'MOVE', 'Drop', NULL, '1', '2023-01-07 17:39:56', NULL),
(2, '2022', 'Expelled', 'EXP', 'Drop', NULL, '2', '2023-01-07 17:39:56', NULL),
(3, '2022', 'Beginning of Year', 'EBY', 'Add', 'Y', '3', '2023-01-07 17:39:56', NULL),
(4, '2022', 'From Other District', 'OTHER', 'Add', NULL, '4', '2023-01-07 17:39:56', NULL),
(5, '2022', 'Transferred in District', 'TRAN', 'Drop', NULL, '5', '2023-01-07 17:39:56', NULL),
(6, '2022', 'Transferred in District', 'EMY', 'Add', NULL, '6', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_field_categories`
--

CREATE TABLE `student_field_categories` (
  `id` int(11) NOT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `sort_order` decimal(10,0) DEFAULT NULL,
  `columns` decimal(4,0) DEFAULT NULL,
  `include` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `student_field_categories`
--

INSERT INTO `student_field_categories` (`id`, `title`, `sort_order`, `columns`, `include`, `created_at`, `updated_at`) VALUES
(1, 'General Info', '1', NULL, NULL, '2023-01-07 17:39:56', NULL),
(2, 'Medical', '3', NULL, NULL, '2023-01-07 17:39:56', NULL),
(3, 'Addresses & Contacts', '2', NULL, NULL, '2023-01-07 17:39:56', NULL),
(4, 'Comments', '4', NULL, NULL, '2023-01-07 17:39:56', NULL),
(5, 'Food Service', '5', NULL, 'Food_Service/Student', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `student_medical`
--

CREATE TABLE `student_medical` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `type` varchar(25) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `medical_date` date DEFAULT NULL,
  `comments` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_alerts`
--

CREATE TABLE `student_medical_alerts` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_medical_visits`
--

CREATE TABLE `student_medical_visits` (
  `id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `school_date` date DEFAULT NULL,
  `time_in` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `time_out` varchar(20) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `reason` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `result` varchar(100) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `comments` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_comments`
--

CREATE TABLE `student_mp_comments` (
  `student_id` int(11) NOT NULL,
  `syear` decimal(4,0) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_mp_stats`
--

CREATE TABLE `student_mp_stats` (
  `student_id` int(11) NOT NULL,
  `marking_period_id` int(11) NOT NULL,
  `cum_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_rank` int(11) DEFAULT NULL,
  `mp_rank` int(11) DEFAULT NULL,
  `class_size` int(11) DEFAULT NULL,
  `sum_weighted_factors` decimal(22,16) DEFAULT NULL,
  `sum_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_weighted_factors` int(11) DEFAULT NULL,
  `count_unweighted_factors` int(11) DEFAULT NULL,
  `grade_level_short` varchar(3) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `cr_weighted_factors` decimal(22,16) DEFAULT NULL,
  `cr_unweighted_factors` decimal(22,16) DEFAULT NULL,
  `count_cr_factors` int(11) DEFAULT NULL,
  `cum_cr_weighted_factor` decimal(22,16) DEFAULT NULL,
  `cum_cr_unweighted_factor` decimal(22,16) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `gp_credits` decimal(22,16) DEFAULT NULL,
  `cr_credits` decimal(22,16) DEFAULT NULL,
  `comments` varchar(75) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_comments`
--

CREATE TABLE `student_report_card_comments` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `course_period_id` int(11) NOT NULL,
  `report_card_comment_id` int(11) NOT NULL,
  `comment` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

-- --------------------------------------------------------

--
-- Table structure for table `student_report_card_grades`
--

CREATE TABLE `student_report_card_grades` (
  `syear` decimal(4,0) NOT NULL,
  `school_id` int(11) NOT NULL,
  `student_id` int(11) NOT NULL,
  `course_period_id` int(11) DEFAULT NULL,
  `report_card_grade_id` int(11) DEFAULT NULL,
  `report_card_comment_id` int(11) DEFAULT NULL,
  `comment` text COLLATE utf8mb4_unicode_520_ci,
  `grade_percent` decimal(4,1) DEFAULT NULL,
  `marking_period_id` int(11) NOT NULL,
  `grade_letter` varchar(5) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `weighted_gp` decimal(7,2) DEFAULT NULL,
  `unweighted_gp` decimal(7,2) DEFAULT NULL,
  `gp_scale` decimal(7,2) DEFAULT NULL,
  `credit_attempted` decimal(22,16) DEFAULT NULL,
  `credit_earned` decimal(22,16) DEFAULT NULL,
  `credit_category` varchar(10) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `course_title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `id` int(11) NOT NULL,
  `school` text COLLATE utf8mb4_unicode_520_ci,
  `class_rank` varchar(1) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `credit_hours` decimal(6,2) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Triggers `student_report_card_grades`
--
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_delete` AFTER DELETE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(OLD.student_id, OLD.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_insert` AFTER INSERT ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `srcg_mp_stats_update` AFTER UPDATE ON `student_report_card_grades` FOR EACH ROW CALL t_update_mp_stats(NEW.student_id, NEW.marking_period_id)
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `templates`
--

CREATE TABLE `templates` (
  `modname` varchar(150) COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `staff_id` int(11) NOT NULL,
  `template` longtext COLLATE utf8mb4_unicode_520_ci,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `templates`
--

INSERT INTO `templates` (`modname`, `staff_id`, `template`, `created_at`, `updated_at`) VALUES
('Custom/CreateParents.php', 0, 'Dear __PARENT_NAME__,\r\nA parent account for the __SCHOOL_ID__ has been created to access school information and student information for the following students:\r\n__ASSOCIATED_STUDENTS__\r\nYour account credentials are:\r\nUsername: __USERNAME__\r\nPassword: __PASSWORD__\r\nA link to the SIS website and instructions for access are available on the school\'s website__BLOCK2__Dear __PARENT_NAME__,\r\nThe following students have been added to your parent account on the SIS:\r\n__ASSOCIATED_STUDENTS__', '2023-01-07 17:39:56', NULL),
('Custom/NotifyParents.php', 0, 'Dear __PARENT_NAME__,\r\nA parent account for the __SCHOOL_ID__ has been created to access school information and student information for the following students:\r\n__ASSOCIATED_STUDENTS__\r\nYour account credentials are:\r\nUsername: __USERNAME__\r\nPassword: __PASSWORD__\r\nA link to the SIS website and instructions for access are available on the school\'s website', '2023-01-07 17:39:56', NULL),
('Grades/HonorRoll.php', 0, '<br /><br /><br />\r\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__SCHOOL_ID__</strong><br /></span><br /><span style=\"font-size: xx-large;\">We hereby recognize<br /><br /></span></div>\r\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\"><strong>__FIRST_NAME__ __LAST_NAME__</strong><br /><br /></span></div>\r\n<div style=\"text-align: center;\"><span style=\"font-size: xx-large;\">Who has completed all the academic requirements for <br />Honor Roll</span></div>', '2023-01-07 17:39:56', NULL),
('Grades/Transcripts.php', 0, '<h2 style=\"text-align: center;\">Studies Certificate</h2>\r\n<p>The Principal here undersigned certifies:</p>\r\n<p>That __FIRST_NAME__ __LAST_NAME__ attended at this school the following courses corresponding to grade __GRADE_ID__ in year __YEAR__ with the following grades and credit hours.</p>\r\n<p>__BLOCK2__</p>\r\n<p>&nbsp;</p>\r\n<table style=\"border-collapse: collapse; width: 100%;\" border=\"0\" cellpadding=\"10\"><tbody><tr>\r\n<td style=\"width: 50%; text-align: center;\"><hr />\r\n<p>Signature</p>\r\n<p>&nbsp;</p><hr />\r\n<p>Title</p></td>\r\n<td style=\"width: 50%; text-align: center;\"><hr />\r\n<p>Signature</p>\r\n<p>&nbsp;</p><hr />\r\n<p>Title</p></td></tr></tbody></table>', '2023-01-07 17:39:56', NULL),
('Students/Letters.php', 0, '<p></p>', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Stand-in structure for view `transcript_grades`
-- (See below for the actual view)
--
CREATE TABLE `transcript_grades` (
`syear` decimal(4,0)
,`school_id` int(11)
,`marking_period_id` int(11)
,`mp_type` varchar(20)
,`short_name` varchar(10)
,`parent_id` bigint(11)
,`grandparent_id` bigint(20)
,`parent_end_date` date
,`end_date` date
,`student_id` int(11)
,`cum_weighted_gpa` decimal(32,19)
,`cum_unweighted_gpa` decimal(32,19)
,`cum_rank` int(11)
,`mp_rank` int(11)
,`class_size` int(11)
,`weighted_gpa` decimal(36,23)
,`unweighted_gpa` decimal(36,23)
,`grade_level_short` varchar(3)
,`comment` text
,`grade_percent` decimal(4,1)
,`grade_letter` varchar(5)
,`weighted_gp` decimal(7,2)
,`unweighted_gp` decimal(7,2)
,`gp_scale` decimal(7,2)
,`credit_attempted` decimal(22,16)
,`credit_earned` decimal(22,16)
,`course_title` text
,`school_name` text
,`school_scale` decimal(10,3)
,`cr_weighted_gpa` decimal(36,23)
,`cr_unweighted_gpa` decimal(36,23)
,`cum_cr_weighted_gpa` decimal(32,19)
,`cum_cr_unweighted_gpa` decimal(32,19)
,`class_rank` varchar(1)
,`comments` varchar(75)
,`credit_hours` decimal(6,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `user_profiles`
--

CREATE TABLE `user_profiles` (
  `id` int(11) NOT NULL,
  `profile` varchar(30) COLLATE utf8mb4_unicode_520_ci DEFAULT NULL,
  `title` text COLLATE utf8mb4_unicode_520_ci NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT NULL ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_520_ci;

--
-- Dumping data for table `user_profiles`
--

INSERT INTO `user_profiles` (`id`, `profile`, `title`, `created_at`, `updated_at`) VALUES
(0, 'student', 'Student', '2023-01-07 17:39:56', NULL),
(1, 'admin', 'Administrator', '2023-01-07 17:39:56', NULL),
(2, 'teacher', 'Teacher', '2023-01-07 17:39:56', NULL),
(3, 'parent', 'Parent', '2023-01-07 17:39:56', NULL);

-- --------------------------------------------------------

--
-- Structure for view `course_details`
--
DROP TABLE IF EXISTS `course_details`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`%` SQL SECURITY DEFINER VIEW `course_details`  AS SELECT `cp`.`school_id` AS `school_id`, `cp`.`syear` AS `syear`, `cp`.`marking_period_id` AS `marking_period_id`, `c`.`subject_id` AS `subject_id`, `cp`.`course_id` AS `course_id`, `cp`.`course_period_id` AS `course_period_id`, `cp`.`teacher_id` AS `teacher_id`, `c`.`title` AS `course_title`, `cp`.`title` AS `cp_title`, `cp`.`grade_scale_id` AS `grade_scale_id`, `cp`.`mp` AS `mp`, `cp`.`credits` AS `credits` FROM (`course_periods` `cp` join `courses` `c`) WHERE (`cp`.`course_id` = `c`.`course_id`)  ;

-- --------------------------------------------------------

--
-- Structure for view `enroll_grade`
--
DROP TABLE IF EXISTS `enroll_grade`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`%` SQL SECURITY DEFINER VIEW `enroll_grade`  AS SELECT `e`.`id` AS `id`, `e`.`syear` AS `syear`, `e`.`school_id` AS `school_id`, `e`.`student_id` AS `student_id`, `e`.`start_date` AS `start_date`, `e`.`end_date` AS `end_date`, `sg`.`short_name` AS `short_name`, `sg`.`title` AS `title` FROM (`student_enrollment` `e` join `school_gradelevels` `sg`) WHERE (`e`.`grade_id` = `sg`.`id`)  ;

-- --------------------------------------------------------

--
-- Structure for view `marking_periods`
--
DROP TABLE IF EXISTS `marking_periods`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`%` SQL SECURITY DEFINER VIEW `marking_periods`  AS SELECT `school_marking_periods`.`marking_period_id` AS `marking_period_id`, 'Rosario' AS `mp_source`, `school_marking_periods`.`syear` AS `syear`, `school_marking_periods`.`school_id` AS `school_id`, (case when (`school_marking_periods`.`mp` = 'FY') then 'year' when (`school_marking_periods`.`mp` = 'SEM') then 'semester' when (`school_marking_periods`.`mp` = 'QTR') then 'quarter' else NULL end) AS `mp_type`, `school_marking_periods`.`title` AS `title`, `school_marking_periods`.`short_name` AS `short_name`, `school_marking_periods`.`sort_order` AS `sort_order`, (case when (`school_marking_periods`.`parent_id` > 0) then `school_marking_periods`.`parent_id` else -(1) end) AS `parent_id`, (case when ((select `smp`.`parent_id` from `school_marking_periods` `smp` where (`smp`.`marking_period_id` = `school_marking_periods`.`parent_id`)) > 0) then (select `smp`.`parent_id` from `school_marking_periods` `smp` where (`smp`.`marking_period_id` = `school_marking_periods`.`parent_id`)) else -(1) end) AS `grandparent_id`, `school_marking_periods`.`start_date` AS `start_date`, `school_marking_periods`.`end_date` AS `end_date`, `school_marking_periods`.`post_start_date` AS `post_start_date`, `school_marking_periods`.`post_end_date` AS `post_end_date`, `school_marking_periods`.`does_grades` AS `does_grades`, `school_marking_periods`.`does_comments` AS `does_comments` FROM `school_marking_periods` union select `history_marking_periods`.`marking_period_id` AS `marking_period_id`,'History' AS `mp_source`,`history_marking_periods`.`syear` AS `syear`,`history_marking_periods`.`school_id` AS `school_id`,`history_marking_periods`.`mp_type` AS `mp_type`,`history_marking_periods`.`name` AS `title`,`history_marking_periods`.`short_name` AS `short_name`,NULL AS `sort_order`,`history_marking_periods`.`parent_id` AS `parent_id`,-(1) AS `grandparent_id`,NULL AS `start_date`,`history_marking_periods`.`post_end_date` AS `end_date`,NULL AS `post_start_date`,`history_marking_periods`.`post_end_date` AS `post_end_date`,'Y' AS `does_grades`,NULL AS `does_comments` from `history_marking_periods`  ;

-- --------------------------------------------------------

--
-- Structure for view `transcript_grades`
--
DROP TABLE IF EXISTS `transcript_grades`;

CREATE ALGORITHM=UNDEFINED DEFINER=`rosariosis_user`@`%` SQL SECURITY DEFINER VIEW `transcript_grades`  AS SELECT `mp`.`syear` AS `syear`, `mp`.`school_id` AS `school_id`, `mp`.`marking_period_id` AS `marking_period_id`, `mp`.`mp_type` AS `mp_type`, `mp`.`short_name` AS `short_name`, `mp`.`parent_id` AS `parent_id`, `mp`.`grandparent_id` AS `grandparent_id`, (select `mp2`.`end_date` from (`student_report_card_grades` join `marking_periods` `mp2` on((`mp2`.`marking_period_id` = `student_report_card_grades`.`marking_period_id`))) where ((`student_report_card_grades`.`student_id` = `sms`.`student_id`) and ((`student_report_card_grades`.`marking_period_id` = `mp`.`parent_id`) or (`student_report_card_grades`.`marking_period_id` = `mp`.`grandparent_id`)) and (`student_report_card_grades`.`course_title` = `srcg`.`course_title`)) order by `mp2`.`end_date` limit 1) AS `parent_end_date`, `mp`.`end_date` AS `end_date`, `sms`.`student_id` AS `student_id`, (`sms`.`cum_weighted_factor` * coalesce(`schools`.`reporting_gp_scale`,(select `schools`.`reporting_gp_scale` from `schools` where (`mp`.`school_id` = `schools`.`id`) order by `schools`.`syear` limit 1))) AS `cum_weighted_gpa`, (`sms`.`cum_unweighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_unweighted_gpa`, `sms`.`cum_rank` AS `cum_rank`, `sms`.`mp_rank` AS `mp_rank`, `sms`.`class_size` AS `class_size`, ((`sms`.`sum_weighted_factors` / `sms`.`count_weighted_factors`) * `schools`.`reporting_gp_scale`) AS `weighted_gpa`, ((`sms`.`sum_unweighted_factors` / `sms`.`count_unweighted_factors`) * `schools`.`reporting_gp_scale`) AS `unweighted_gpa`, `sms`.`grade_level_short` AS `grade_level_short`, `srcg`.`comment` AS `comment`, `srcg`.`grade_percent` AS `grade_percent`, `srcg`.`grade_letter` AS `grade_letter`, `srcg`.`weighted_gp` AS `weighted_gp`, `srcg`.`unweighted_gp` AS `unweighted_gp`, `srcg`.`gp_scale` AS `gp_scale`, `srcg`.`credit_attempted` AS `credit_attempted`, `srcg`.`credit_earned` AS `credit_earned`, `srcg`.`course_title` AS `course_title`, `srcg`.`school` AS `school_name`, `schools`.`reporting_gp_scale` AS `school_scale`, ((`sms`.`cr_weighted_factors` / `sms`.`count_cr_factors`) * `schools`.`reporting_gp_scale`) AS `cr_weighted_gpa`, ((`sms`.`cr_unweighted_factors` / `sms`.`count_cr_factors`) * `schools`.`reporting_gp_scale`) AS `cr_unweighted_gpa`, (`sms`.`cum_cr_weighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_cr_weighted_gpa`, (`sms`.`cum_cr_unweighted_factor` * `schools`.`reporting_gp_scale`) AS `cum_cr_unweighted_gpa`, `srcg`.`class_rank` AS `class_rank`, `sms`.`comments` AS `comments`, `srcg`.`credit_hours` AS `credit_hours` FROM (((`marking_periods` `mp` join `student_report_card_grades` `srcg` on((`mp`.`marking_period_id` = `srcg`.`marking_period_id`))) join `student_mp_stats` `sms` on(((`sms`.`marking_period_id` = `mp`.`marking_period_id`) and (`sms`.`student_id` = `srcg`.`student_id`)))) left join `schools` on((((`mp`.`school_id` = `schools`.`id`) and (`mp`.`mp_source` <> 'History') and (`mp`.`syear` = `schools`.`syear`)) or ((`mp`.`mp_source` = 'History') and (`mp`.`syear` = (select `schools`.`syear` from `schools` where (`mp`.`school_id` = `schools`.`id`) order by `schools`.`syear` limit 1)))))) ORDER BY `srcg`.`course_period_id` ASC  ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `accounting_payments_ind1` (`staff_id`),
  ADD KEY `accounting_payments_ind2` (`amount`);

--
-- Indexes for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `address`
--
ALTER TABLE `address`
  ADD PRIMARY KEY (`address_id`),
  ADD KEY `address_3` (`zipcode`),
  ADD KEY `address_4` (`street`);

--
-- Indexes for table `address_fields`
--
ALTER TABLE `address_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `address_desc_ind2` (`type`),
  ADD KEY `address_fields_ind3` (`category_id`);

--
-- Indexes for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD PRIMARY KEY (`syear`,`school_id`,`school_date`,`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD PRIMARY KEY (`calendar_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `attendance_codes_ind3` (`short_name`);

--
-- Indexes for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `attendance_completed`
--
ALTER TABLE `attendance_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`,`table_name`);

--
-- Indexes for table `attendance_day`
--
ALTER TABLE `attendance_day`
  ADD PRIMARY KEY (`student_id`,`school_date`);

--
-- Indexes for table `attendance_period`
--
ALTER TABLE `attendance_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `attendance_period_ind1` (`student_id`),
  ADD KEY `attendance_period_ind2` (`period_id`),
  ADD KEY `attendance_period_ind4` (`school_date`),
  ADD KEY `attendance_period_ind5` (`attendance_code`);

--
-- Indexes for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `billing_payments_ind2` (`amount`),
  ADD KEY `billing_payments_ind3` (`refunded_payment_id`);

--
-- Indexes for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `courses`
--
ALTER TABLE `courses`
  ADD PRIMARY KEY (`course_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `courses_ind2` (`subject_id`);

--
-- Indexes for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD PRIMARY KEY (`course_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  ADD PRIMARY KEY (`course_period_school_periods_id`),
  ADD UNIQUE KEY `course_period_id` (`course_period_id`,`period_id`);

--
-- Indexes for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD PRIMARY KEY (`subject_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `custom_fields`
--
ALTER TABLE `custom_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `custom_desc_ind2` (`type`),
  ADD KEY `custom_fields_ind3` (`category_id`);

--
-- Indexes for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility`
--
ALTER TABLE `eligibility`
  ADD KEY `eligibility_ind1` (`student_id`,`course_period_id`,`school_date`);

--
-- Indexes for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `eligibility_completed`
--
ALTER TABLE `eligibility_completed`
  ADD PRIMARY KEY (`staff_id`,`school_date`,`period_id`);

--
-- Indexes for table `food_service_accounts`
--
ALTER TABLE `food_service_accounts`
  ADD PRIMARY KEY (`account_id`);

--
-- Indexes for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  ADD PRIMARY KEY (`category_id`),
  ADD UNIQUE KEY `food_service_categories_title` (`school_id`,`menu_id`,`title`);

--
-- Indexes for table `food_service_items`
--
ALTER TABLE `food_service_items`
  ADD PRIMARY KEY (`item_id`),
  ADD UNIQUE KEY `food_service_items_short_name` (`school_id`,`short_name`);

--
-- Indexes for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  ADD PRIMARY KEY (`menu_id`),
  ADD UNIQUE KEY `food_service_menus_title` (`school_id`,`title`);

--
-- Indexes for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  ADD PRIMARY KEY (`menu_item_id`);

--
-- Indexes for table `food_service_staff_accounts`
--
ALTER TABLE `food_service_staff_accounts`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_staff_transaction_items`
--
ALTER TABLE `food_service_staff_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `food_service_staff_transaction_items_ind1` (`transaction_id`);

--
-- Indexes for table `food_service_student_accounts`
--
ALTER TABLE `food_service_student_accounts`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `barcode` (`barcode`);

--
-- Indexes for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `food_service_transaction_items`
--
ALTER TABLE `food_service_transaction_items`
  ADD PRIMARY KEY (`item_id`,`transaction_id`),
  ADD KEY `food_service_transaction_items_ind1` (`transaction_id`);

--
-- Indexes for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  ADD PRIMARY KEY (`assignment_id`),
  ADD KEY `gradebook_assignments_ind3` (`assignment_type_id`);

--
-- Indexes for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  ADD PRIMARY KEY (`assignment_type_id`);

--
-- Indexes for table `gradebook_grades`
--
ALTER TABLE `gradebook_grades`
  ADD PRIMARY KEY (`student_id`,`assignment_id`,`course_period_id`),
  ADD KEY `gradebook_grades_ind1` (`assignment_id`);

--
-- Indexes for table `grades_completed`
--
ALTER TABLE `grades_completed`
  ADD PRIMARY KEY (`staff_id`,`marking_period_id`,`course_period_id`);

--
-- Indexes for table `history_marking_periods`
--
ALTER TABLE `history_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `history_marking_period_ind1` (`school_id`),
  ADD KEY `history_marking_period_ind2` (`syear`);

--
-- Indexes for table `lunch_period`
--
ALTER TABLE `lunch_period`
  ADD PRIMARY KEY (`student_id`,`school_date`,`period_id`),
  ADD KEY `lunch_period_ind2` (`period_id`),
  ADD KEY `lunch_period_ind3` (`attendance_code`),
  ADD KEY `lunch_period_ind4` (`school_date`);

--
-- Indexes for table `moodlexrosario`
--
ALTER TABLE `moodlexrosario`
  ADD PRIMARY KEY (`column`,`rosario_id`);

--
-- Indexes for table `people`
--
ALTER TABLE `people`
  ADD PRIMARY KEY (`person_id`),
  ADD KEY `people_1` (`last_name`,`first_name`);

--
-- Indexes for table `people_fields`
--
ALTER TABLE `people_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_desc_ind2` (`type`),
  ADD KEY `people_fields_ind3` (`category_id`);

--
-- Indexes for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  ADD PRIMARY KEY (`id`),
  ADD KEY `people_join_contacts_ind1` (`person_id`);

--
-- Indexes for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `profile_exceptions`
--
ALTER TABLE `profile_exceptions`
  ADD PRIMARY KEY (`profile_id`,`modname`);

--
-- Indexes for table `program_config`
--
ALTER TABLE `program_config`
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `program_user_config`
--
ALTER TABLE `program_user_config`
  ADD KEY `program_user_config_ind1` (`user_id`,`program`);

--
-- Indexes for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  ADD PRIMARY KEY (`id`),
  ADD KEY `report_card_comment_codes_ind1` (`school_id`);

--
-- Indexes for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `resources`
--
ALTER TABLE `resources`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `schedule`
--
ALTER TABLE `schedule`
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_ind3` (`student_id`,`marking_period_id`,`start_date`,`end_date`);

--
-- Indexes for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD PRIMARY KEY (`request_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `schedule_requests_ind1` (`student_id`,`course_id`,`syear`);

--
-- Indexes for table `schools`
--
ALTER TABLE `schools`
  ADD PRIMARY KEY (`id`,`syear`),
  ADD KEY `schools_ind1` (`syear`);

--
-- Indexes for table `school_fields`
--
ALTER TABLE `school_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_desc_ind2` (`type`);

--
-- Indexes for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_gradelevels_ind1` (`school_id`);

--
-- Indexes for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD PRIMARY KEY (`marking_period_id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `school_marking_periods_ind1` (`parent_id`),
  ADD KEY `school_marking_periods_ind2` (`syear`,`school_id`,`start_date`,`end_date`);

--
-- Indexes for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD PRIMARY KEY (`period_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `staff`
--
ALTER TABLE `staff`
  ADD PRIMARY KEY (`staff_id`),
  ADD UNIQUE KEY `staff_ind4` (`username`,`syear`),
  ADD KEY `staff_ind1` (`staff_id`,`syear`),
  ADD KEY `staff_ind2` (`last_name`,`first_name`),
  ADD KEY `staff_ind3` (`schools`);

--
-- Indexes for table `staff_exceptions`
--
ALTER TABLE `staff_exceptions`
  ADD PRIMARY KEY (`user_id`,`modname`);

--
-- Indexes for table `staff_fields`
--
ALTER TABLE `staff_fields`
  ADD PRIMARY KEY (`id`),
  ADD KEY `staff_desc_ind2` (`type`),
  ADD KEY `staff_fields_ind3` (`category_id`);

--
-- Indexes for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`student_id`),
  ADD UNIQUE KEY `username` (`username`),
  ADD KEY `name` (`last_name`,`first_name`,`middle_name`);

--
-- Indexes for table `students_join_address`
--
ALTER TABLE `students_join_address`
  ADD PRIMARY KEY (`id`),
  ADD KEY `stu_addr_meets_2` (`address_id`),
  ADD KEY `students_join_address_ind1` (`student_id`);

--
-- Indexes for table `students_join_people`
--
ALTER TABLE `students_join_people`
  ADD PRIMARY KEY (`id`),
  ADD KEY `relations_meets_2` (`address_id`);

--
-- Indexes for table `students_join_users`
--
ALTER TABLE `students_join_users`
  ADD PRIMARY KEY (`student_id`,`staff_id`);

--
-- Indexes for table `student_assignments`
--
ALTER TABLE `student_assignments`
  ADD PRIMARY KEY (`assignment_id`,`student_id`);

--
-- Indexes for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD PRIMARY KEY (`id`),
  ADD KEY `school_id` (`school_id`,`syear`),
  ADD KEY `student_enrollment_2` (`grade_id`),
  ADD KEY `student_enrollment_4` (`start_date`,`end_date`);

--
-- Indexes for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_medical`
--
ALTER TABLE `student_medical`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  ADD PRIMARY KEY (`id`);

--
-- Indexes for table `student_mp_comments`
--
ALTER TABLE `student_mp_comments`
  ADD PRIMARY KEY (`student_id`,`syear`,`marking_period_id`);

--
-- Indexes for table `student_mp_stats`
--
ALTER TABLE `student_mp_stats`
  ADD PRIMARY KEY (`student_id`,`marking_period_id`);

--
-- Indexes for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD PRIMARY KEY (`syear`,`student_id`,`course_period_id`,`marking_period_id`,`report_card_comment_id`),
  ADD KEY `school_id` (`school_id`,`syear`);

--
-- Indexes for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  ADD PRIMARY KEY (`id`),
  ADD KEY `student_report_card_grades_ind4` (`marking_period_id`);

--
-- Indexes for table `templates`
--
ALTER TABLE `templates`
  ADD PRIMARY KEY (`modname`,`staff_id`);

--
-- Indexes for table `user_profiles`
--
ALTER TABLE `user_profiles`
  ADD PRIMARY KEY (`id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address`
--
ALTER TABLE `address`
  MODIFY `address_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_fields`
--
ALTER TABLE `address_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `address_field_categories`
--
ALTER TABLE `address_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  MODIFY `calendar_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_fees`
--
ALTER TABLE `billing_fees`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `billing_payments`
--
ALTER TABLE `billing_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `calendar_events`
--
ALTER TABLE `calendar_events`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `courses`
--
ALTER TABLE `courses`
  MODIFY `course_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_periods`
--
ALTER TABLE `course_periods`
  MODIFY `course_period_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_period_school_periods`
--
ALTER TABLE `course_period_school_periods`
  MODIFY `course_period_school_periods_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `course_subjects`
--
ALTER TABLE `course_subjects`
  MODIFY `subject_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `custom_fields`
--
ALTER TABLE `custom_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000012;

--
-- AUTO_INCREMENT for table `discipline_fields`
--
ALTER TABLE `discipline_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `food_service_categories`
--
ALTER TABLE `food_service_categories`
  MODIFY `category_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_items`
--
ALTER TABLE `food_service_items`
  MODIFY `item_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_menus`
--
ALTER TABLE `food_service_menus`
  MODIFY `menu_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `food_service_menu_items`
--
ALTER TABLE `food_service_menu_items`
  MODIFY `menu_item_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  MODIFY `transaction_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  MODIFY `transaction_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignments`
--
ALTER TABLE `gradebook_assignments`
  MODIFY `assignment_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `gradebook_assignment_types`
--
ALTER TABLE `gradebook_assignment_types`
  MODIFY `assignment_type_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people`
--
ALTER TABLE `people`
  MODIFY `person_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_fields`
--
ALTER TABLE `people_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_field_categories`
--
ALTER TABLE `people_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `people_join_contacts`
--
ALTER TABLE `people_join_contacts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_notes`
--
ALTER TABLE `portal_notes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_polls`
--
ALTER TABLE `portal_polls`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `portal_poll_questions`
--
ALTER TABLE `portal_poll_questions`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_codes`
--
ALTER TABLE `report_card_comment_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_comment_code_scales`
--
ALTER TABLE `report_card_comment_code_scales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=16;

--
-- AUTO_INCREMENT for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `resources`
--
ALTER TABLE `resources`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  MODIFY `request_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `schools`
--
ALTER TABLE `schools`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `school_fields`
--
ALTER TABLE `school_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `school_gradelevels`
--
ALTER TABLE `school_gradelevels`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- AUTO_INCREMENT for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  MODIFY `marking_period_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=8;

--
-- AUTO_INCREMENT for table `school_periods`
--
ALTER TABLE `school_periods`
  MODIFY `period_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `staff`
--
ALTER TABLE `staff`
  MODIFY `staff_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `staff_fields`
--
ALTER TABLE `staff_fields`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=200000002;

--
-- AUTO_INCREMENT for table `staff_field_categories`
--
ALTER TABLE `staff_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- AUTO_INCREMENT for table `students`
--
ALTER TABLE `students`
  MODIFY `student_id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `students_join_address`
--
ALTER TABLE `students_join_address`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `students_join_people`
--
ALTER TABLE `students_join_people`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=2;

--
-- AUTO_INCREMENT for table `student_enrollment_codes`
--
ALTER TABLE `student_enrollment_codes`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `student_field_categories`
--
ALTER TABLE `student_field_categories`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `student_medical`
--
ALTER TABLE `student_medical`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_alerts`
--
ALTER TABLE `student_medical_alerts`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_medical_visits`
--
ALTER TABLE `student_medical_visits`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_report_card_grades`
--
ALTER TABLE `student_report_card_grades`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `user_profiles`
--
ALTER TABLE `user_profiles`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=4;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `accounting_incomes`
--
ALTER TABLE `accounting_incomes`
  ADD CONSTRAINT `accounting_incomes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_payments`
--
ALTER TABLE `accounting_payments`
  ADD CONSTRAINT `accounting_payments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `accounting_salaries`
--
ALTER TABLE `accounting_salaries`
  ADD CONSTRAINT `accounting_salaries_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendar`
--
ALTER TABLE `attendance_calendar`
  ADD CONSTRAINT `attendance_calendar_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_calendars`
--
ALTER TABLE `attendance_calendars`
  ADD CONSTRAINT `attendance_calendars_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_codes`
--
ALTER TABLE `attendance_codes`
  ADD CONSTRAINT `attendance_codes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `attendance_code_categories`
--
ALTER TABLE `attendance_code_categories`
  ADD CONSTRAINT `attendance_code_categories_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `billing_fees`
--
ALTER TABLE `billing_fees`
  ADD CONSTRAINT `billing_fees_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `billing_payments`
--
ALTER TABLE `billing_payments`
  ADD CONSTRAINT `billing_payments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `calendar_events`
--
ALTER TABLE `calendar_events`
  ADD CONSTRAINT `calendar_events_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `courses`
--
ALTER TABLE `courses`
  ADD CONSTRAINT `courses_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_periods`
--
ALTER TABLE `course_periods`
  ADD CONSTRAINT `course_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `course_subjects`
--
ALTER TABLE `course_subjects`
  ADD CONSTRAINT `course_subjects_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_field_usage`
--
ALTER TABLE `discipline_field_usage`
  ADD CONSTRAINT `discipline_field_usage_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `discipline_referrals`
--
ALTER TABLE `discipline_referrals`
  ADD CONSTRAINT `discipline_referrals_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `eligibility_activities`
--
ALTER TABLE `eligibility_activities`
  ADD CONSTRAINT `eligibility_activities_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_staff_transactions`
--
ALTER TABLE `food_service_staff_transactions`
  ADD CONSTRAINT `food_service_staff_transactions_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `food_service_transactions`
--
ALTER TABLE `food_service_transactions`
  ADD CONSTRAINT `food_service_transactions_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `portal_notes`
--
ALTER TABLE `portal_notes`
  ADD CONSTRAINT `portal_notes_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `portal_polls`
--
ALTER TABLE `portal_polls`
  ADD CONSTRAINT `portal_polls_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `program_config`
--
ALTER TABLE `program_config`
  ADD CONSTRAINT `program_config_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comments`
--
ALTER TABLE `report_card_comments`
  ADD CONSTRAINT `report_card_comments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_comment_categories`
--
ALTER TABLE `report_card_comment_categories`
  ADD CONSTRAINT `report_card_comment_categories_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grades`
--
ALTER TABLE `report_card_grades`
  ADD CONSTRAINT `report_card_grades_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `report_card_grade_scales`
--
ALTER TABLE `report_card_grade_scales`
  ADD CONSTRAINT `report_card_grade_scales_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule`
--
ALTER TABLE `schedule`
  ADD CONSTRAINT `schedule_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `schedule_requests`
--
ALTER TABLE `schedule_requests`
  ADD CONSTRAINT `schedule_requests_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_marking_periods`
--
ALTER TABLE `school_marking_periods`
  ADD CONSTRAINT `school_marking_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `school_periods`
--
ALTER TABLE `school_periods`
  ADD CONSTRAINT `school_periods_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_enrollment`
--
ALTER TABLE `student_enrollment`
  ADD CONSTRAINT `student_enrollment_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);

--
-- Constraints for table `student_report_card_comments`
--
ALTER TABLE `student_report_card_comments`
  ADD CONSTRAINT `student_report_card_comments_ibfk_1` FOREIGN KEY (`school_id`,`syear`) REFERENCES `schools` (`id`, `syear`);
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
