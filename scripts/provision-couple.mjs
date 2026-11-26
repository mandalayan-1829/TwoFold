import { createClient } from '@supabase/supabase-js';

function fail(message) {
    console.error(`\nProvisioning failed: ${message}`);
    process.exit(1);
}

function requiredEnv(name) {
    const value = process.env[name]?.trim();

    if (!value) {
        fail(`Missing required environment variable: ${name}`);
    }

    return value;
}

function validateUuid(value, name) {
    const uuidPattern =
        /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

    if (!uuidPattern.test(value)) {
        fail(`${name} must contain a valid UUID.`);
    }
}

function validateDisplayName(value, name) {
    const trimmed = value.trim();

    if (trimmed.length < 1 || trimmed.length > 80) {
        fail(`${name} must contain between 1 and 80 characters.`);
    }

    return trimmed;
}

function validateSpaceName(value) {
    const trimmed = value.trim();

    if (trimmed.length < 1 || trimmed.length > 100) {
        fail('COUPLE_SPACE_NAME must contain between 1 and 100 characters.');
    }

    return trimmed;
}

function validateAnniversaryDate(value) {
    if (!value) {
        return null;
    }

    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
        fail('ANNIVERSARY_DATE must use YYYY-MM-DD format.');
    }

    const date = new Date(`${value}T00:00:00.000Z`);

    if (
        Number.isNaN(date.getTime()) ||
        date.toISOString().slice(0, 10) !== value
    ) {
        fail('ANNIVERSARY_DATE is not a valid calendar date.');
    }

    return value;
}

async function main() {
    console.log('\nTwoFold Initial Couple Provisioning');
    console.log('-----------------------------------');

    const supabaseUrl = requiredEnv('SUPABASE_URL');
    const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');

    const ownerUserId = requiredEnv('OWNER_USER_ID');
    const partnerUserId = requiredEnv('PARTNER_USER_ID');

    const ownerDisplayName = validateDisplayName(
        requiredEnv('OWNER_DISPLAY_NAME'),
        'OWNER_DISPLAY_NAME'
    );

    const partnerDisplayName = validateDisplayName(
        requiredEnv('PARTNER_DISPLAY_NAME'),
        'PARTNER_DISPLAY_NAME'
    );

    const spaceName = validateSpaceName(
        process.env.COUPLE_SPACE_NAME?.trim() || 'TwoFold'
    );

    const anniversaryDate = validateAnniversaryDate(
        process.env.ANNIVERSARY_DATE?.trim() || ''
    );

    validateUuid(ownerUserId, 'OWNER_USER_ID');
    validateUuid(partnerUserId, 'PARTNER_USER_ID');

    if (ownerUserId.toLowerCase() === partnerUserId.toLowerCase()) {
        fail('Owner and partner must be different Auth accounts.');
    }

    let parsedUrl;

    try {
        parsedUrl = new URL(supabaseUrl);
    } catch {
        fail('SUPABASE_URL is not a valid URL.');
    }

    if (!['http:', 'https:'].includes(parsedUrl.protocol)) {
        fail('SUPABASE_URL must use HTTP or HTTPS.');
    }

    const supabase = createClient(supabaseUrl, serviceRoleKey, {
        auth: {
            autoRefreshToken: false,
            persistSession: false,
            detectSessionInUrl: false,
        },
    });

    console.log('\nVerifying owner Auth account...');

    const { data: ownerData, error: ownerError } =
        await supabase.auth.admin.getUserById(ownerUserId);

    if (ownerError || !ownerData?.user) {
        fail('Owner Auth account could not be verified.');
    }

    console.log('Owner Auth account verified.');

    console.log('\nVerifying partner Auth account...');

    const { data: partnerData, error: partnerError } =
        await supabase.auth.admin.getUserById(partnerUserId);

    if (partnerError || !partnerData?.user) {
        fail('Partner Auth account could not be verified.');
    }

    console.log('Partner Auth account verified.');

    console.log('\nCalling atomic database provisioning RPC...');

    const { data: coupleId, error: provisioningError } =
        await supabase.rpc('provision_initial_couple', {
            p_owner_user_id: ownerUserId,
            p_partner_user_id: partnerUserId,
            p_owner_display_name: ownerDisplayName,
            p_partner_display_name: partnerDisplayName,
            p_space_name: spaceName,
            p_anniversary_date: anniversaryDate,
        });

    if (provisioningError) {
        console.error('\nDatabase provisioning was unsuccessful.');
        console.error(`Error: ${provisioningError.message}`);

        if (provisioningError.code) {
            console.error(`Database error code: ${provisioningError.code}`);
        }

        process.exit(1);
    }

    if (typeof coupleId !== 'string') {
        fail('The provisioning RPC returned an unexpected response.');
    }

    console.log('\n-----------------------------------');
    console.log('TwoFold provisioning successful!');
    console.log(`Couple ID: ${coupleId}`);
    console.log('Created: 1 couple, 2 profiles, 2 settings, 2 memberships.');
    console.log('-----------------------------------\n');
}

main().catch(() => {
    fail('An unexpected error occurred. Check the environment and local Supabase services.');
});
